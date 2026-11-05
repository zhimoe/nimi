## Metal layer-effect renderer for the paper shredder.
##
## Two passes mirror MyGo's mask + LayerEffect idea:
##   1. strip quads (and the intact card) are rendered into an RGBA8 mask;
##      the mask stores the source UV in RG and coverage in A;
##   2. a full-screen shader samples the mask and the paper texture, then the
##      slot hardware is drawn as solid geometry.
##
## This is intentionally independent of AppKit: callers can render to an
## offscreen texture (tests/smoke) or attach the renderer to a CAMetalLayer
## drawable in a native window. All calls are main-thread only.

import std/[math]

import ../effects/shred

when defined(macosx):
  import ../platform/darwin/objc
else:
  type
    Id = pointer
    NSUInteger = uint

when defined(macosx):
  import std/dynlib

type
  MTLOrigin {.bycopy.} = object
    x*, y*, z*: NSUInteger
  MTLSize {.bycopy.} = object
    w*, h*, d*: NSUInteger
  MTLRegion {.bycopy.} = object
    origin*: MTLOrigin
    size*: MTLSize
  MTLClearColor {.bycopy.} = object
    r*, g*, b*, a*: float64

  MetalShred* = ref object
    ok*: bool
    error*: string
    device*: Id
    queue*: Id
    maskTex*: Id
    sourceTex*: Id
    targetTex*: Id
    targetW*, targetH*: int
    maskW*, maskH*: int
    sourceW*, sourceH*: int
    maskPipeline*: Id
    layerPipeline*: Id
    solidPipeline*: Id
    maskBuffers*: array[2, Id]
    maskBufferBytes*: int
    maskBufferIndex*: int
    solidBuffer*: Id
    solidBufferBytes*: int

const
  MTLPixelFormatRGBA8Unorm = NSUInteger(70)
  MTLPixelFormatBGRA8Unorm = NSUInteger(80)
  MTLPrimitiveTypeTriangle = NSUInteger(3)
  MTLLoadActionClear = NSUInteger(2)
  MTLStoreActionStore = NSUInteger(1)
  MTLResourceStorageModeShared = NSUInteger(0)
  MTLTextureUsageShaderRead = NSUInteger(1)
  MTLTextureUsageRenderTarget = NSUInteger(4)

when defined(macosx):
  let
    metalLib = loadLib("/System/Library/Frameworks/Metal.framework/Metal")
    metalDeviceFn = cast[proc(): Id {.cdecl.}](
      symAddr(metalLib, "MTLCreateSystemDefaultDevice"))

  type
    MsgSendError = proc(a: Id, s: SEL, b: Id, c: Id,
                        e: ptr Id): Id {.cdecl.}
    MsgSendTextureDesc = proc(a: Id, s: SEL, pixelFormat: NSUInteger,
                              width, height: NSUInteger,
                              mipmapped: bool): Id {.cdecl.}
    MsgSendBufferBytes = proc(a: Id, s: SEL, bytes: pointer,
                              length, options: NSUInteger): Id {.cdecl.}
    MsgSendBufferLength = proc(a: Id, s: SEL, length,
                               options: NSUInteger): Id {.cdecl.}
    MsgSendReplaceRegion = proc(a: Id, s: SEL, region: MTLRegion,
                                level: NSUInteger, bytes: pointer,
                                bytesPerRow: NSUInteger) {.cdecl.}
    MsgSendGetBytes = proc(a: Id, s: SEL, bytes: pointer, bytesPerRow: NSUInteger,
                           region: MTLRegion,
                           level: NSUInteger) {.cdecl.}
    MsgSendSetVertexBuffer = proc(a: Id, s: SEL, buffer: Id, offset,
                                  index: NSUInteger) {.cdecl.}
    MsgSendSetVertexBytes = proc(a: Id, s: SEL, bytes: pointer, length,
                                 index: NSUInteger) {.cdecl.}
    MsgSendSetFragmentTexture = proc(a: Id, s: SEL, texture: Id,
                                     index: NSUInteger) {.cdecl.}
    MsgSendSetFragmentBytes = proc(a: Id, s: SEL, bytes: pointer, length,
                                   index: NSUInteger) {.cdecl.}
    MsgSendDraw = proc(a: Id, s: SEL, typ: NSUInteger, start,
                       count: NSUInteger) {.cdecl.}
    MsgSendSetPixelFormat = proc(a: Id, s: SEL, format: NSUInteger) {.cdecl.}
    MsgSendSetClearColor = proc(a: Id, s: SEL, color: MTLClearColor) {.cdecl.}
    MsgSendSetTexture = proc(a: Id, s: SEL, texture: Id) {.cdecl.}
    MsgSendSetPipeline = proc(a: Id, s: SEL, pipeline: Id) {.cdecl.}
    MsgSendSetFunction = proc(a: Id, s: SEL, fn: Id) {.cdecl.}

  proc mtlSel(name: string): SEL = sel(name)

  proc newTexture(device: Id, fmt: NSUInteger, w, h: int, usage: NSUInteger): Id =
    let desc = cast[MsgSendTextureDesc](msgSend)(
      loadClass("MTLTextureDescriptor"),
      mtlSel("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),
      fmt, NSUInteger(w), NSUInteger(h), false)
    if desc == nil:
      return nil
    sendVoidUInt(desc, mtlSel("setUsage:"), usage)
    sendVoidUInt(desc, mtlSel("setStorageMode:"), MTLResourceStorageModeShared)
    result = sendId1(device, mtlSel("newTextureWithDescriptor:"), desc)

  proc pipeline(device: Id, library: Id, vertexName, fragmentName: string,
                pixelFormat: NSUInteger, errorOut: var string): Id =
    let vf = sendId1(library, mtlSel("newFunctionWithName:"),
                     nsString(vertexName))
    let ff = sendId1(library, mtlSel("newFunctionWithName:"),
                     nsString(fragmentName))
    if vf == nil or ff == nil:
      errorOut = "missing Metal shader function"
      return nil
    let desc = send0(loadClass("MTLRenderPipelineDescriptor"), sel("new"))
    cast[MsgSendSetFunction](msgSend)(desc, mtlSel("setVertexFunction:"), vf)
    cast[MsgSendSetFunction](msgSend)(desc, mtlSel("setFragmentFunction:"), ff)
    let atts = send0(desc, mtlSel("colorAttachments"))
    let att = sendIdUInt(atts, mtlSel("objectAtIndexedSubscript:"), 0)
    cast[MsgSendSetPixelFormat](msgSend)(att, mtlSel("setPixelFormat:"),
                                         pixelFormat)
    var err: Id = nil
    result = cast[MsgSendError](msgSend)(
      device, mtlSel("newRenderPipelineStateWithDescriptor:error:"),
      desc, nil, addr err)
    if result == nil:
      if err != nil:
        errorOut = goString(send0(err, mtlSel("localizedDescription")))
      else:
        errorOut = "Metal pipeline creation failed"
    release(vf)
    release(ff)
    release(desc)

  const shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct MaskOut {
  float4 position [[position]];
  float2 uv;
};

vertex MaskOut vs_mask(const device float4 *verts [[buffer(0)]],
                       constant float2 &size [[buffer(1)]],
                       uint vid [[vertex_id]]) {
  float4 v = verts[vid];
  float2 p = v.xy / size;
  MaskOut o;
  o.position = float4(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);
  o.uv = v.zw;
  return o;
}

fragment float4 fs_mask(MaskOut in [[stage_in]]) {
  return float4(in.uv, 0.0, 1.0);
}

struct LayerOut {
  float4 position [[position]];
  float2 uv;
};

vertex LayerOut vs_full(uint vid [[vertex_id]]) {
  float2 p = float2((vid == 1 || vid == 2 || vid == 4) ? 1.0 : 0.0,
                    (vid == 2 || vid == 4 || vid == 5) ? 1.0 : 0.0);
  LayerOut o;
  o.position = float4(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);
  o.uv = p;
  return o;
}

fragment float4 fs_layer(LayerOut in [[stage_in]],
                         texture2d<float> mask [[texture(0)]],
                         texture2d<float> source [[texture(1)]]) {
  constexpr sampler s(coord::normalized, filter::linear,
                      address::clamp_to_edge);
  float4 m = mask.sample(s, in.uv);
  if (m.a < 0.01) {
    discard_fragment();
  }
  float2 uv = m.rg / max(m.a, 0.0001);
  return source.sample(s, uv);
}

vertex float4 vs_solid(const device float2 *pos [[buffer(0)]],
                       constant float2 &size [[buffer(1)]],
                       uint vid [[vertex_id]]) {
  float2 p = pos[vid] / size;
  return float4(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);
}

fragment float4 fs_solid(constant float4 &color [[buffer(0)]]) {
  return color;
}
"""

  proc compileLibrary(device: Id, errorOut: var string): Id =
    var err: Id = nil
    result = cast[MsgSendError](msgSend)(
      device, mtlSel("newLibraryWithSource:options:error:"),
      nsString(shaderSource), nil, addr err)
    if result == nil:
      if err != nil:
        errorOut = goString(send0(err, mtlSel("localizedDescription")))
      else:
        errorOut = "Metal shader compilation failed"

  proc uploadSource(device: Id, pixels: seq[uint8], w, h: int): Id =
    let tex = newTexture(device, MTLPixelFormatRGBA8Unorm, w, h,
                         MTLTextureUsageShaderRead)
    if tex == nil:
      return nil
    var data = pixels
    let region = MTLRegion(
      origin: MTLOrigin(x: 0, y: 0, z: 0),
      size: MTLSize(w: NSUInteger(w), h: NSUInteger(h), d: 1))
    cast[MsgSendReplaceRegion](msgSend)(
      tex, mtlSel("replaceRegion:mipmapLevel:withBytes:bytesPerRow:"),
      region, 0, addr data[0], NSUInteger(w * 4))
    result = tex

  proc newPipelineBuffer(device: Id, size: int): Id =
    cast[MsgSendBufferLength](msgSend)(
      device, mtlSel("newBufferWithLength:options:"), NSUInteger(size),
      MTLResourceStorageModeShared)

  proc ensureTarget(m: MetalShred, w, h: int) =
    if m.targetTex != nil and m.targetW == w and m.targetH == h:
      return
    if m.targetTex != nil:
      release(m.targetTex)
    m.targetTex = newTexture(m.device, MTLPixelFormatBGRA8Unorm, w, h,
                             MTLTextureUsageShaderRead or
                             MTLTextureUsageRenderTarget)
    m.targetW = w
    m.targetH = h

  proc pushVert(v: var seq[float32], x, y, u, vv: float32) =
    v.add x
    v.add y
    v.add u
    v.add vv

  proc pushQuad(v: var seq[float32],
                ax, ay, bx, by, cx, cy, dx, dy: float32,
                u0, v0, u1, v1: float32) =
    # two triangles: a,b,c and a,c,d
    pushVert(v, ax, ay, u0, v0)
    pushVert(v, bx, by, u1, v0)
    pushVert(v, cx, cy, u1, v1)
    pushVert(v, ax, ay, u0, v0)
    pushVert(v, cx, cy, u1, v1)
    pushVert(v, dx, dy, u0, v1)

  proc buildMaskVerts(m: MetalShred, sim: ShredSim, stageW, stageH, slot,
                      cardTop: float32): seq[float32] =
    let sxScale = float32(m.maskW) / max(stageW, 1)
    let syScale = float32(m.maskH) / max(stageH, 1)
    let paperX = stageW / 2 - float32(m.sourceW) / 2
    let c = sim.config
    let stripW = c.width / float32(c.count)
    let segH = c.height / float32(c.segments)

    # Intact card above the slot. Only the visible source rows are encoded.
    if cardTop < slot:
      let visibleH = min(float32(m.sourceH), slot - cardTop)
      if visibleH > 0.5:
        let v1 = visibleH / float32(m.sourceH)
        pushQuad(result,
                 (paperX) * sxScale, cardTop * syScale,
                 (paperX + c.width) * sxScale, cardTop * syScale,
                 (paperX + c.width) * sxScale, (cardTop + visibleH) * syScale,
                 (paperX) * sxScale, (cardTop + visibleH) * syScale,
                 0, 0, 1, v1)

    for i in 0 ..< c.count:
      let nodes = sim.strips[i].nodes
      if nodes.len < 2:
        continue
      let half = stripW * 0.46
      var left = newSeq[tuple[x, y: float32]](nodes.len)
      var right = newSeq[tuple[x, y: float32]](nodes.len)
      for k in 0 ..< nodes.len:
        let before = nodes[max(0, k - 1)]
        let after = nodes[min(nodes.len - 1, k + 1)]
        var tx = after.x - before.x
        var ty = after.y - before.y
        let tl = max(0.0001'f32, hypot(tx, ty))
        tx /= tl
        ty /= tl
        left[k] = (x: paperX + nodes[k].x - ty * half,
                   y: slot + nodes[k].y + tx * half)
        right[k] = (x: paperX + nodes[k].x + ty * half,
                    y: slot + nodes[k].y - tx * half)
      let u0 = float32(i) / float32(c.count)
      let u1 = float32(i + 1) / float32(c.count)
      for k in 0 ..< nodes.len - 1:
        let sy = float32(c.segments - 1 - k) * segH
        let v0 = sy / float32(m.sourceH)
        let v1 = (sy + segH) / float32(m.sourceH)
        pushQuad(result,
                 left[k + 1].x * sxScale, left[k + 1].y * syScale,
                 right[k + 1].x * sxScale, right[k + 1].y * syScale,
                 right[k].x * sxScale, right[k].y * syScale,
                 left[k].x * sxScale, left[k].y * syScale,
                 u0, v0, u1, v1)

  proc encodeMask(m: MetalShred, sim: ShredSim, stageW, stageH, slot,
                  cardTop: float32, cb: Id) =
    let verts = m.buildMaskVerts(sim, stageW, stageH, slot, cardTop)
    var idx = 0
    if verts.len > 0:
      let bytes = verts.len * 4
      if bytes > m.maskBufferBytes:
        for i in 0 ..< 2:
          if m.maskBuffers[i] != nil:
            release(m.maskBuffers[i])
          m.maskBuffers[i] = newPipelineBuffer(m.device, bytes)
        m.maskBufferBytes = bytes
      idx = m.maskBufferIndex
      m.maskBufferIndex = 1 - idx
      if m.maskBuffers[idx] != nil:
        let dest = send0(m.maskBuffers[idx], mtlSel("contents"))
        if dest != nil:
          copyMem(dest, unsafeAddr verts[0], bytes)
        else:
          idx = -1
      else:
        idx = -1

    let pass = send0(loadClass("MTLRenderPassDescriptor"),
                     mtlSel("renderPassDescriptor"))
    let atts = send0(pass, mtlSel("colorAttachments"))
    let att = sendIdUInt(atts, mtlSel("objectAtIndexedSubscript:"), 0)
    cast[MsgSendSetTexture](msgSend)(att, mtlSel("setTexture:"), m.maskTex)
    sendVoidUInt(att, mtlSel("setLoadAction:"), MTLLoadActionClear)
    sendVoidUInt(att, mtlSel("setStoreAction:"), MTLStoreActionStore)
    cast[MsgSendSetClearColor](msgSend)(
      att, mtlSel("setClearColor:"), MTLClearColor(r: 0, g: 0, b: 0, a: 0))
    let enc = sendId1(cb, mtlSel("renderCommandEncoderWithDescriptor:"), pass)
    if enc == nil:
      return
    if idx >= 0 and verts.len > 0:
      cast[MsgSendSetPipeline](msgSend)(enc, mtlSel("setRenderPipelineState:"),
                                        m.maskPipeline)
      cast[MsgSendSetVertexBuffer](msgSend)(
        enc, mtlSel("setVertexBuffer:offset:atIndex:"),
        m.maskBuffers[idx], 0, 0)
      var size = (float32(m.maskW), float32(m.maskH))
      cast[MsgSendSetVertexBytes](msgSend)(
        enc, mtlSel("setVertexBytes:length:atIndex:"),
        addr size, 8, 1)
      cast[MsgSendDraw](msgSend)(
        enc, mtlSel("drawPrimitives:vertexStart:vertexCount:"),
        MTLPrimitiveTypeTriangle, 0, NSUInteger(verts.len div 4))
    sendVoid(enc, mtlSel("endEncoding"))

  proc encodeLayer(m: MetalShred, stageW, stageH, slot: float32, target: Id,
                   cb: Id) =
    let pass = send0(loadClass("MTLRenderPassDescriptor"),
                     mtlSel("renderPassDescriptor"))
    let atts = send0(pass, mtlSel("colorAttachments"))
    let att = sendIdUInt(atts, mtlSel("objectAtIndexedSubscript:"), 0)
    cast[MsgSendSetTexture](msgSend)(att, mtlSel("setTexture:"), target)
    sendVoidUInt(att, mtlSel("setLoadAction:"), MTLLoadActionClear)
    sendVoidUInt(att, mtlSel("setStoreAction:"), MTLStoreActionStore)
    cast[MsgSendSetClearColor](msgSend)(
      att, mtlSel("setClearColor:"),
      MTLClearColor(r: 0.125, g: 0.125, b: 0.125, a: 1))
    let enc = sendId1(cb, mtlSel("renderCommandEncoderWithDescriptor:"), pass)
    if enc == nil:
      return
    cast[MsgSendSetPipeline](msgSend)(enc, mtlSel("setRenderPipelineState:"),
                                      m.layerPipeline)
    cast[MsgSendSetFragmentTexture](msgSend)(
      enc, mtlSel("setFragmentTexture:atIndex:"), m.maskTex, 0)
    cast[MsgSendSetFragmentTexture](msgSend)(
      enc, mtlSel("setFragmentTexture:atIndex:"), m.sourceTex, 1)
    cast[MsgSendDraw](msgSend)(
      enc, mtlSel("drawPrimitives:vertexStart:vertexCount:"),
      MTLPrimitiveTypeTriangle, 0, 6)

    # Slot hardware: a gray bar and a dark slit. Keep these in stage space so
    # they line up with the mask/texture passes at any drawable resolution.
    let slotW = 370.0'f32
    let sx = stageW / 2 - slotW / 2
    var solid: seq[float32]
    proc addSolid(x, y: float32) =
      solid.add x
      solid.add y
    proc addRect(x, y, w, h: float32) =
      addSolid(x, y)
      addSolid(x + w, y)
      addSolid(x + w, y + h)
      addSolid(x, y)
      addSolid(x + w, y + h)
      addSolid(x, y + h)
    addRect(sx, slot - 10, slotW, 20)
    addRect(sx + 14, slot - 2, slotW - 28, 4)
    if solid.len > 0:
      if m.solidBuffer == nil or m.solidBufferBytes < solid.len * 4:
        if m.solidBuffer != nil:
          release(m.solidBuffer)
        m.solidBuffer = newPipelineBuffer(m.device, solid.len * 4)
        m.solidBufferBytes = solid.len * 4
      if m.solidBuffer != nil:
        let dest = send0(m.solidBuffer, mtlSel("contents"))
        if dest != nil:
          copyMem(dest, unsafeAddr solid[0], solid.len * 4)
          cast[MsgSendSetPipeline](msgSend)(
            enc, mtlSel("setRenderPipelineState:"), m.solidPipeline)
          cast[MsgSendSetVertexBuffer](msgSend)(
            enc, mtlSel("setVertexBuffer:offset:atIndex:"), m.solidBuffer, 0, 0)
          # The solid vertex shader receives stage-space pixels; use the
          # drawable size for its NDC conversion, not the mask size.
          var drawableSize = (float32(stageW), float32(stageH))
          cast[MsgSendSetVertexBytes](msgSend)(
            enc, mtlSel("setVertexBytes:length:atIndex:"), addr drawableSize, 8, 1)
          var gray = (0.333'f32, 0.333'f32, 0.333'f32, 1'f32)
          cast[MsgSendSetFragmentBytes](msgSend)(
            enc, mtlSel("setFragmentBytes:length:atIndex:"), addr gray, 16, 0)
          cast[MsgSendDraw](msgSend)(
            enc, mtlSel("drawPrimitives:vertexStart:vertexCount:"),
            MTLPrimitiveTypeTriangle, 0, 6)
          # Dark slit, second draw with a different fragment color.
          var dark = (0.067'f32, 0.067'f32, 0.067'f32, 1'f32)
          cast[MsgSendSetFragmentBytes](msgSend)(
            enc, mtlSel("setFragmentBytes:length:atIndex:"), addr dark, 16, 0)
          cast[MsgSendDraw](msgSend)(
            enc, mtlSel("drawPrimitives:vertexStart:vertexCount:"),
            MTLPrimitiveTypeTriangle, 6, 6)
    sendVoid(enc, mtlSel("endEncoding"))

  proc initMetalShred(m: MetalShred, pixels: seq[uint8], sourceW,
                      sourceH: int, maskW, maskH: int): bool =
    m.device = metalDeviceFn()
    if m.device == nil:
      m.error = "no Metal device"
      return false
    m.queue = send0(m.device, mtlSel("newCommandQueue"))
    if m.queue == nil:
      m.error = "cannot create Metal command queue"
      return false
    var err = ""
    let library = compileLibrary(m.device, err)
    if library == nil:
      m.error = err
      return false
    m.maskPipeline = pipeline(m.device, library, "vs_mask", "fs_mask",
                              MTLPixelFormatRGBA8Unorm, err)
    if m.maskPipeline == nil:
      m.error = err
      return false
    m.layerPipeline = pipeline(m.device, library, "vs_full", "fs_layer",
                               MTLPixelFormatBGRA8Unorm, err)
    if m.layerPipeline == nil:
      m.error = err
      return false
    m.solidPipeline = pipeline(m.device, library, "vs_solid", "fs_solid",
                               MTLPixelFormatBGRA8Unorm, err)
    if m.solidPipeline == nil:
      m.error = err
      return false
    m.sourceW = sourceW
    m.sourceH = sourceH
    m.maskW = maskW
    m.maskH = maskH
    m.maskTex = newTexture(m.device, MTLPixelFormatRGBA8Unorm, maskW, maskH,
                           MTLTextureUsageShaderRead or
                           MTLTextureUsageRenderTarget)
    if m.maskTex == nil:
      m.error = "cannot allocate mask texture"
      return false
    m.sourceTex = uploadSource(m.device, pixels, sourceW, sourceH)
    if m.sourceTex == nil:
      m.error = "cannot upload paper texture"
      return false
    result = true

  proc renderToTarget*(m: MetalShred, sim: ShredSim, stageW, stageH, slot,
                       cardTop: float32, target: Id): bool =
    if m == nil or not m.ok or target == nil:
      return false
    let cb = send0(m.queue, mtlSel("commandBuffer"))
    if cb == nil:
      return false
    m.encodeMask(sim, stageW, stageH, slot, cardTop, cb)
    m.encodeLayer(stageW, stageH, slot, target, cb)
    sendVoid(cb, mtlSel("commit"))
    sendVoid(cb, mtlSel("waitUntilCompleted"))
    result = true

  proc renderToLayer*(m: MetalShred, sim: ShredSim, layer: Id,
                      stageW, stageH, slot, cardTop: float32): bool =
    ## Render one frame into a CAMetalLayer's next drawable. The mask pass and
    ## the layer pass are encoded into one command buffer, then presented.
    if m == nil or not m.ok or layer == nil:
      return false
    let drawable = send0(layer, mtlSel("nextDrawable"))
    if drawable == nil:
      return false
    let target = send0(drawable, mtlSel("texture"))
    if target == nil:
      return false
    let cb = send0(m.queue, mtlSel("commandBuffer"))
    if cb == nil:
      return false
    m.encodeMask(sim, stageW, stageH, slot, cardTop, cb)
    m.encodeLayer(stageW, stageH, slot, target, cb)
    sendVoidId(cb, mtlSel("presentDrawable:"), drawable)
    sendVoid(cb, mtlSel("commit"))
    result = true

  proc renderOffscreen*(m: MetalShred, sim: ShredSim, width, height: int,
                        slot, cardTop: float32): seq[uint8] =
    if m == nil or not m.ok:
      return
    m.ensureTarget(width, height)
    if m.targetTex == nil:
      return
    if not m.renderToTarget(sim, float32(width), float32(height), slot,
                            cardTop, m.targetTex):
      return
    let stride = width * 4
    result = newSeq[uint8](stride * height)
    let region = MTLRegion(
      origin: MTLOrigin(x: 0, y: 0, z: 0),
      size: MTLSize(w: NSUInteger(width), h: NSUInteger(height), d: 1))
    cast[MsgSendGetBytes](msgSend)(
      m.targetTex, mtlSel("getBytes:bytesPerRow:fromRegion:mipmapLevel:"),
      addr result[0], NSUInteger(stride), region, 0)
    # The drawable-compatible target is BGRA8Unorm; expose RGBA to callers.
    for i in 0 ..< width * height:
      let p = i * 4
      let b = result[p]
      result[p] = result[p + 2]
      result[p + 2] = b

proc close*(m: MetalShred) =
  ## Release Metal textures, pipelines, buffers, queue, and device. Safe to
  ## call more than once. Do not render afterwards without creating a new
  ## MetalShred.
  if m == nil:
    return
  when defined(macosx):
    for tex in [m.maskTex, m.sourceTex, m.targetTex]:
      if tex != nil:
        release(tex)
    for pipe in [m.maskPipeline, m.layerPipeline, m.solidPipeline]:
      if pipe != nil:
        release(pipe)
    for buf in m.maskBuffers:
      if buf != nil:
        release(buf)
    if m.solidBuffer != nil:
      release(m.solidBuffer)
    if m.queue != nil:
      release(m.queue)
    if m.device != nil:
      release(m.device)
  m.maskTex = nil
  m.sourceTex = nil
  m.targetTex = nil
  m.maskPipeline = nil
  m.layerPipeline = nil
  m.solidPipeline = nil
  m.maskBuffers = [nil, nil]
  m.solidBuffer = nil
  m.queue = nil
  m.device = nil
  m.targetW = 0
  m.targetH = 0
  m.ok = false

proc newMetalShred*(pixels: seq[uint8], sourceW, sourceH: int,
                    maskW = 1024, maskH = 512): MetalShred =
  result = MetalShred()
  when defined(macosx):
    if pixels.len < sourceW * sourceH * 4:
      result.error = "paper pixel buffer is too small"
      return
    if not result.initMetalShred(pixels, sourceW, sourceH, maskW, maskH):
      return
    result.ok = true
  else:
    result.error = "Metal is only available on macOS"
