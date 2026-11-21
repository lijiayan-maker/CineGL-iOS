# Design notes

[简体中文](原理与设计取舍.md) | English

> This is for anyone who wants to know what the GPU in this camera is actually busy with — including me, three months from now, having forgotten all of it.
> The pipeline itself (log, 3D LUTs, Dual Kawase, grain…) is covered in the Android version's notes, so I won't reheat those leftovers here.
> This one is about **what changed on the way to iOS, why, and which holes I fell into**. For usage and build commands, see the [README](../README.en.md).

## The short version: same pipeline, different engine

My rule hasn't changed: **every pass has to map to something in a real film camera**.

```
Real world                         CineGL (iOS)
──────────                         ────────────
Lens      distortion, fringing, →  input pass (CINInput.metal)
          vignetting
Exposure  highlights scatter    →  glow pass (Dual Kawase pyramid)
          into halation
Develop   color comes out       →  3D LUT in the film pass
Silver    grain                 →  noise in the film pass
Projector looking at the film   →  present pass (which also draws zebra, peaking and the waveform)
```

The passes, their parameters and every line of color math match the Android version one to one. I even ported the Android C++ unit tests to XCTest assertion by assertion, without changing a single number. With both sides in lockstep, whenever one of them does something weird, the other one is a ready-made control group.

What changed is the layer underneath: **OpenGL ES became Metal, C++ became C + simd, and Kotlin + Compose became Objective-C + UIKit**.

---

## Why not keep OpenGL ES

The lazy option was right there: iOS has OpenGL ES, the GLSL would run as-is, and both platforms could share one set of shaders. I passed on it for one reason: **performance is the only metric**.

- Apple deprecated OpenGL ES back in iOS 12. It still runs, through a compatibility layer that translates to Metal — like taking the frontage road next to the highway.
- Metal has something GLES on iOS doesn't: `CVMetalTextureCache`. The camera's `CVPixelBuffer` sits on an IOSurface, and Metal can simply borrow it as a texture without copying a byte. Recording works the same way: the GPU draws straight into the writer's pixel buffer.
- Half-float render targets (the halation pyramid needs them) are standard equipment in Metal. No checking `EXT_color_buffer_half_float` first and falling back to RGBA8 like on Android.
- Shaders are compiled **at build time** into `default.metallib`. The one bug that made it all the way to a phone in the Android notes — the halation texture and the halation strength both named `uHalation` — wouldn't survive ⌘B here.

The price: every shader had to be rewritten in MSL. GLSL and MSL are cousins, though — `vec3` becomes `float3`, `texture()` becomes `.sample()`, `mix(lo, hi, step())` becomes `select()`. Grunt work. The part that actually needed thinking is next.

---

## Coordinates: one more flip

The Android notes call coordinates a minefield. Metal dug the mine a little deeper: **Metal textures have their origin at the top left**, GL at the bottom left.

My choice was "leave the core alone, flip at the border":

- every matrix and every uv still follows the GL convention (bottom-left origin, v up), so the math in `CINFrameGeometry` and its unit tests match the Android version word for word;
- when a shader samples a texture the pipeline drew itself, it goes through one helper, `tc(uv) = (u, 1 - v)`;
- camera buffers and photo bitmaps already have "row 0 at the top", in image coordinates, so they aren't flipped.

A happy accident: Metal render targets already read back top row first, so the `flipY` Android needed for `glReadPixels` on photos, and the `kFlipV` for the thumbnail atlas, are both unnecessary on iOS. Three flips became one, and I sleep better.

### No mysterious SurfaceTexture matrix

On Android, camera frames land in a `SurfaceTexture`, and the system hands you a transform matrix with the sensor rotation and mirroring already worked out. iOS offers no such service: `AVCaptureVideoDataOutput` delivers buffers in the **native sensor orientation** (landscape, needing a 90° clockwise turn to be upright), and the front camera isn't mirrored.

You can ask AVFoundation to rotate (`videoRotationAngle = 90`), but that physically rotates every frame — performance again. So buffers stay as they are and the GPU does the rotation and mirroring: the input pass samples through a matrix anyway, and one more matrix costs nothing.

Better still, the Android version already had that matrix — `stillInputMatrix`, originally written for photos (JPEGs come in sensor orientation too). On iOS, **preview and photos use the same matrix**. Two birds, one stone.

---

## Camera buffers: YCbCr, not BGRA

Asking `AVCaptureVideoDataOutput` for BGRA is the easy way: the shader can use it directly. But the camera works in YUV internally, so the system has to convert first — another full-frame shuffle.

I ask for `420f` (8-bit bi-planar YCbCr), borrow luma and chroma as two textures (`R8` + `RG8`), and do the matrix multiply to RGB in the input pass myself. It's the same idea as Android's `samplerExternalOES` quietly doing YUV → RGB during sampling, except this time I'm the one doing it:

- the matrix follows the buffer's attachment: BT.709 / 601 / 2020;
- full range (0–255) and video range (16–235) each get their own offsets;
- Apple Log uses 10-bit `x420`, with the data in the top 10 bits of a 16-bit word, so a sample reads `v16 / 65535` and needs an extra factor of `65535 / 64 / 1023`. Miss it and black drifts by a hair — invisible to the eye, very visible to a unit test.

Photos go the other way: I ask `AVCapturePhotoOutput` for **uncompressed BGRA**. Android can only get a JPEG and decode it, which is like pressing the photo into a cracker and then soaking it back; iOS can hand over the raw ingredients, so why bother.

---

## Log: from an ISP curve to Apple Log

Android's third log mode samples CineLog into 64 points and feeds them to the ISP (`TONEMAP_CURVE`). iOS has no such hook, but it has something more authentic: **Apple Log** on iPhone 15 Pro and later — 10-bit log straight from the camera, in Rec.2020 primaries no less.

I don't let Apple Log flow through the whole pipeline. The input pass **decodes it to linear Rec.709 first, then encodes it as CineLog**. Halation, LUTs and grain never need to know where the signal came from: inside the pipeline there are still only two encodings, Rec.709 and CineLog, just like on Android. Apple Log is simply one more entrance — an extra security lane at the airport that leads to the same departure lounge.

Its curve is piecewise (a parabola in the shadows, a log above), with the constants copied from Apple's white paper into both `CINColor.m` and the shaders. Unit tests check that the pieces join continuously, that encode and decode invert each other, and that 18% gray lands at 0.488.

---

## Manual controls: what iOS gives you and what it doesn't

**Exposure**: just like Camera2, iOS only has "fully auto" and "fully manual (custom)" — no shutter priority, no ISO priority. The semi-auto idea carries over unchanged: record `ISO × exposure time` while auto, lock one, compute the other. Even the unit tests use the same numbers.

**White balance**: here iOS is more generous than Android — it can convert "temperature + tint" straight into device gains. So on devices that support custom gains, the temperature is **absolute**, and it starts from the current auto white balance temperature, so the image doesn't jump the moment you switch to manual. Android can only offset from AWB, which is why it treats 5500 K as "change nothing" to avoid the jump. Devices without custom gains (some front cameras) fall back to the Android approach: lock AWB and multiply gains on the GPU.

**Focus**: iOS only reports a lens position from 0 to 1, never meters. Using the thin-lens approximation "lens travel ∝ 1 / subject distance", I convert it linearly to diopters, and the dial happily shows "0.50m". Not exact, but monotonic and it feels right — the same attitude as the white balance slopes in the Android notes.

**Multiple cameras**: the back "triple / dual" virtual devices switch seamlessly between wide and tele, but they often won't let you lock the lens position. When it's manual focus *or* zoom steps, I pick manual: **manual controls are the heart of this app**. The rule is "use the virtual device only if it supports both custom exposure and a locked lens; otherwise use the single wide camera".

---

## Recording: AVAssetWriter and the host clock

Android's `MediaCodec` + `MediaMuxer` pile shrinks to a single `AVAssetWriter` on iOS. The effort saved went into two things.

**First, a frame isn't done until the GPU is done.** Recording frames are drawn by the GPU into pixel buffers, and a committed command buffer isn't a finished one. The obvious move is to append in `addCompletedHandler` — but Metal doesn't promise which thread or which order those callbacks arrive in, and once frames go out of order, the writer drops them for non-increasing timestamps. Instead, frames queue up on a serial queue **in submission order**: each one waits with `waitUntilCompleted`, then goes to the writer. Stopping a recording also queues a "we're done" behind them, so it only counts as stopped once every earlier frame is delivered.

**Second, one clock for picture and sound.** On Android you pick `BOOTTIME` or `MONOTONIC` depending on the camera's timestamp source; iOS is simpler — everything converts to the **host clock**: camera frames through the input port's clock, audio through `AVAudioTime.hostTime`. The writer starts its session at the first video frame and drops any audio that arrives earlier.

The encoder buffer is still always landscape, with a rotation written on the track for portrait clips — same as Android, for the same reasons.

---

## The Simulator: building a camera and a microphone from scratch

The Android emulator at least has a 3D room to shoot. The iOS Simulator? Not a single `AVCaptureDevice`. Bare walls.

No camera means no UI tuning, no screenshots and certainly no manual controls. So I **built a camera** (`CINSimulatedCamera`):

- the scene is drawn once with Core Graphics: wooden walls, a window, a color chart, a monitor, a plant, a lamp. A second "emission" image makes the window and the bulb six times brighter than white, so overexposure, halation and zebra have something to work with;
- a shader scales brightness linearly by `ISO × shutter` and clips anything above 1.0, so it overexposes like a real sensor; manual focus samples a higher mip level to fake defocus; the torch brightens the front of the scene;
- the key step: **it outputs buffers in the same sensor orientation as a real device** (landscape, needing a 90° clockwise turn). The Simulator then runs the real-device path, so rotation, cropping and tap-to-focus coordinates all get exercised instead of taking a Simulator-only shortcut.

The microphone was forced on me. In the Simulator, `AVAudioEngine.inputNode` goes through coreaudiod to the Mac's microphone; on the first run it got stuck on an RPC and the system simply `abort`ed a few seconds later. The nasty part: it was stuck on the main thread. Before the abort, the UI kept showing ISO "A 0", and I spent a while convinced the readout callback was broken. Lesson: **when the UI doesn't update, first check what the main thread is doing.** The Simulator now uses virtual room noise at −45 dBFS instead; the meters still dance and videos still get an audio track.

---

## UI: porting Compose to UIKit one to one

The brief was "exactly the same UI", so I didn't use UIKit's `UISlider` and `UISwitch` — those look like iOS, while the Android version uses Material 3. The slider (a 16 pt track, a 4×44 bar thumb, 6 pt gaps, a small stop dot at the end) and the switch (52×32, a 16 pt gray dot when off, a 24 pt white dot when on) are drawn by hand to Compose's dimensions. Every other font size, spacing and color was copied as a number from the Compose code, not eyeballed from screenshots.

Two UIKit traps, written down so I don't step in them again:

- **`viewWithTag:` checks the view itself first.** In the segmented control, each option's tag is its index and the label inside it had tag 1 — so the second option (also tag 1) got *itself* back from `viewWithTag:1`, and calling `setText:` on a control crashed the app at launch. Subview tags now start at 1001.
- **`UIScrollView` won't take touches away from a `UIControl` by default.** Nearly every row in the settings panel is a tappable switch row, so a finger landing on one meant the panel wouldn't scroll. Overriding `touchesShouldCancelInContentView:` to return YES gives it the same feel as Compose's scroll containers; the sliders use `gestureRecognizerShouldBegin:` to keep horizontal drags for themselves.

And one old lesson carried over from Android: the dial has to **accumulate drag distance internally** instead of recomputing from the value passed back in each time. Exposure compensation is rounded to 1/3-stop steps, so a slow drag of a few pixels per event gets rounded away every time and never moves.

---

## The cold palace: ideas considered and shelved

| Idea | Why not |
|---|---|
| Keep OpenGL ES and share GLSL with Android | Deprecated and running through a compatibility layer; on iOS this project only optimizes for performance |
| Port the Android C++ core as-is | The two repositories are maintained separately; one goal here is practicing Objective-C, C + simd is enough, and simd types are the same types MSL uses |
| `AVCaptureVideoPreviewLayer` for the preview | The preview has to go through our own pipeline, otherwise looks and monitoring tools never reach the screen |
| `AVCaptureMovieFileOutput` for recording | It records the raw camera image, not our rendered result |
| Ask the camera for BGRA | The system would convert every frame; converting bi-planar YCbCr in the shader is free |
| Capture HEIC / JPEG and decode | Uncompressed BGRA goes straight to the GPU, one encode/decode round trip fewer |
| Core Image for the filters | Easier, but this is a study project — writing every pass by hand is the point |
| ProRes log recording | Needs a ProRes encoder path and much more storage; get the H.264 pipeline right first |
| Live Photos | Same as Android: it's a test of encoding and containers, not the GPU |

---

## Exercises

All six exercises from the Android notes work here too (sharpening, tetrahedral interpolation, RGBA16F, a histogram, GPU metering, an RGB parade) — just write them the Metal way. A few iOS-flavored extras:

1. **Histogram with a compute shader**: Metal compute plus atomics, more direct than the waveform's "vertex shader scatter". Compare the timings.
2. **ProRes 422 HQ + Apple Log recording**: swap `CINVideoRecorder`'s encoder for ProRes and, with burn-in off, record footage that's actually ready for a grading app.
3. **Look at one frame in Metal System Trace**: find the most expensive pass in Instruments and try merging the halation and diffusion pyramids into one.
4. **`CVMetalTextureCache` on a device**: remove `keepAlive` on purpose and watch the tearing when the camera reuses an IOSurface — then put it back.

Finish those, and you'll know more than most people about what the GPU inside a camera is doing. At least more than I did three months ago.
