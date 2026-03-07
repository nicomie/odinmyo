package engine

import av "ffmpeg:avcodec"
import u "ffmpeg:avutil"
import t "ffmpeg:types"
import sws "ffmpeg:swscale"
import f "ffmpeg:avformat"

import "core:c"
import "core:mem"
import "core:fmt"


ffmpeg_test :: proc() {
    fmt.println("FFmpeg Test")
    
  
    fmt.printfln("libavcodec version: %v", av.version())
        fmt.println("FFmpeg Test")

        //test()
    
}

test :: proc() {

    fmt_ctx : ^t.Format_Context
    path: cstring = "D:/Projects/odinmyo/engine/videos/60fps.mp4"
    ret := f.open_input(&fmt_ctx, path, nil, nil)
    if ret < 0 {
        fmt.println("Failed to open video file:", ret)
        return
    }

    if f.find_stream_info(fmt_ctx, nil) < 0 {
        fmt.println("Failed to find stream info")
        return    
    }

    stream_index: i32 = -1
    for i in 0..<fmt_ctx.nb_streams {
        if fmt_ctx.streams[i].codecpar.codec_type == .Video {
            stream_index = cast(i32)i
            break
        }
    }
    if stream_index == -1 {
        fmt.println("Failed to find stream info")
        return    
    }

    codecpar := fmt_ctx.streams[stream_index].codecpar
    codec := av.find_decoder(codecpar.codec_id)
    if codec == nil {
        fmt.println("Could not find H264 decoder!")
        return
    }

    ctx: ^t.Codec_Context = av.alloc_context3(codec)
    if ctx == nil {
        fmt.println("Failed to allocate codec context!")
        return
    }

    if av.parameters_to_context(ctx, codecpar) < 0 {
        fmt.println("Failed to copy codec parameters")
        return
    }

    if av.open2(ctx, codec, nil) < 0 {
        fmt.println("Failed to open codec!")
        return
    }

    packet: ^t.Packet = av.packet_alloc()
    frame : ^t.Frame = u.frame_alloc()

    rgb_frame := u.frame_alloc()
    rgb_buffer: rawptr = nil
    rgb_allocated := false
    sws_ctx: ^t.Sws_Context = nil

    for {
        if f.read_frame(fmt_ctx, packet) < 0 do break
        if packet.stream_index != stream_index {
            av.packet_unref(packet)
            continue
        }

        if av.send_packet(ctx, packet) < 0 {
            av.packet_unref(packet)
            continue
        }

        for {
            ret := av.receive_frame(ctx, frame)
            if ret < 0 do break

            // Allocate RGB frame + SwsContext only once width/height are known
            if !rgb_allocated {
                fmt.println("First frame: width=", frame.width, " height=", frame.height, " pix_fmt=", ctx.pix_fmt)

                size := cast(int)(frame.width * frame.height) * 4
                rgb_buffer, _ = mem.alloc(size)
                rgb_frame.data[0] = &mem.byte_slice(rgb_buffer, size)[0]
                rgb_frame.linesize[0] = frame.width * 4

                // Create sws context using actual frame dimensions
                sws_ctx = sws.getContext(
                    frame.width, frame.height, ctx.pix_fmt,
                    frame.width, frame.height, .RGBA,
                    {}, sws.getDefaultFilter(0,0,0,0,0,0,0),
                    nil, nil
                )

                rgb_allocated = true

            }

            fmt.printf("%v \n", frame.best_effort_timestamp)

            sws.scale(
                sws_ctx,
                cast([^]^u8)&frame.data[0],
                &frame.linesize[0],
                0,
                frame.height,
                cast([^]^u8)&rgb_frame.data[0],
                &rgb_frame.linesize[0]
            )
        }

        av.packet_unref(packet)
    }

    fmt.println("FFmpeg decoder initialized successfully!")

    u.frame_free(&frame)
    mem.free(rgb_buffer)
    u.frame_free(&rgb_frame)
    av.packet_free(&packet)
    av.free_context(&ctx)
    sws.freeContext(sws_ctx)
    f.close_input(&fmt_ctx)
}
