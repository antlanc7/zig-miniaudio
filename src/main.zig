const std = @import("std");
const ma = @import("miniaudio.zig");

fn ma_error_check(result: ma.ma_result) !void {
    if (result != ma.MA_SUCCESS) {
        std.debug.print("Error: {}\n", .{result});
        return error.MiniAudioError;
    }
}

export fn data_callback(
    device: [*c]ma.ma_device,
    pOutput: ?*anyopaque,
    pInput: ?*const anyopaque,
    frameCount: ma.ma_uint32,
) callconv(.c) void {
    const d: *ma.ma_device = @ptrCast(device);
    const pEncoder: *ma.ma_encoder = @ptrCast(@alignCast(d.pUserData));
    _ = ma.ma_encoder_write_pcm_frames(pEncoder, pInput, frameCount, null);
    _ = pOutput;
}

pub fn main() !void {
    const stdin = std.fs.File.stdin();
    var stdin_buffer: [1024]u8 = undefined;
    var stdin_reader = stdin.reader(&stdin_buffer);

    var context: ma.ma_context = undefined;
    try ma_error_check(ma.ma_context_init(null, 0, null, &context));
    defer _ = ma.ma_context_uninit(&context);

    var pPlaybackDeviceInfos: [*c]ma.ma_device_info = undefined;
    var pCaptureDeviceInfos: [*c]ma.ma_device_info = undefined;
    var playbackCount: ma.ma_uint32 = undefined;
    var captureCount: ma.ma_uint32 = undefined;

    try ma_error_check(ma.ma_context_get_devices(&context, &pPlaybackDeviceInfos, &playbackCount, &pCaptureDeviceInfos, &captureCount));

    for (0..playbackCount) |i| {
        const info = &pPlaybackDeviceInfos[i];
        std.debug.print("Playback Device {d}: {s}\n", .{ i, info.name });
    }

    for (0..captureCount) |i| {
        const info = &pCaptureDeviceInfos[i];
        std.debug.print("Capture Device {d}: {s}\n", .{ i, info.name });
    }

    std.debug.print("Insert index of capture device: ", .{});
    const index_str_input = try stdin_reader.interface.takeDelimiterExclusive('\n');
    const index_str = std.mem.trim(u8, index_str_input, &std.ascii.whitespace);
    const index = try std.fmt.parseInt(usize, index_str, 10);
    std.debug.print("Selected capture device: {s}\n", .{pCaptureDeviceInfos[index].name});

    const encoder_config = ma.ma_encoder_config_init(ma.ma_encoding_format_wav, ma.ma_format_f32, 2, 44100);
    var encoder: ma.ma_encoder = undefined;

    try ma_error_check(ma.ma_encoder_init_file("output.wav", &encoder_config, &encoder));
    defer ma.ma_encoder_uninit(&encoder);

    var device_config = ma.ma_device_config_init(ma.ma_device_type_capture);
    device_config.capture.pDeviceID = &pCaptureDeviceInfos[index].id;
    device_config.capture.format = encoder.config.format;
    device_config.capture.channels = encoder.config.channels;
    device_config.dataCallback = data_callback;
    device_config.pUserData = &encoder;

    var device: ma.ma_device = undefined;
    try ma_error_check(ma.ma_device_init(&context, &device_config, &device));
    defer ma.ma_device_uninit(&device);

    try ma_error_check(ma.ma_device_start(&device));

    std.debug.print("Recording, press enter to stop\n", .{});

    _ = try stdin_reader.interface.discardDelimiterInclusive('\n');
}
