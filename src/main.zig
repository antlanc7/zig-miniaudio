const std = @import("std");
const ma = @cImport(@cInclude("miniaudio.h"));

fn ma_error_check(result: ma.ma_result) !void {
    if (result != ma.MA_SUCCESS) {
        std.log.err("{}", .{result});
        return error.MiniAudioError;
    }
}

export fn data_callback(
    device: [*c]ma.ma_device,
    pOutput: ?*anyopaque,
    pInput: ?*const anyopaque,
    frameCount: ma.ma_uint32,
) callconv(.c) void {
    _ = pOutput;
    const pEncoder: *ma.ma_encoder = @ptrCast(@alignCast(device.*.pUserData));
    ma_error_check(ma.ma_encoder_write_pcm_frames(pEncoder, pInput, frameCount, null)) catch @panic("ma_encoder_write_pcm_frames");
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const stdin = std.Io.File.stdin();
    var stdin_buffer: [1024]u8 = undefined;
    var stdin_reader = stdin.reader(io, &stdin_buffer);

    while (true) {
        std.debug.print("Choose: \n1: capture\n2: duplex\n", .{});
        const index_str_input = try stdin_reader.interface.takeDelimiterInclusive('\n');
        const index_str = std.mem.trim(u8, index_str_input, &std.ascii.whitespace);

        if (index_str.len == 0) break;

        const index = try std.fmt.parseInt(usize, index_str, 10);
        std.debug.print("Selected: {}\n", .{index});

        if (index == 1) {
            try capture(&stdin_reader.interface);
        } else if (index == 2) {
            try duplex(&stdin_reader.interface);
        }
    }
}

fn capture(stdin_reader: *std.Io.Reader) !void {
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
    const index_str_input = try stdin_reader.takeDelimiterInclusive('\n');
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
    device_config.sampleRate = encoder.config.sampleRate;
    device_config.dataCallback = data_callback;
    device_config.pUserData = &encoder;

    var device: ma.ma_device = undefined;
    try ma_error_check(ma.ma_device_init(&context, &device_config, &device));
    defer ma.ma_device_uninit(&device);

    try ma_error_check(ma.ma_device_start(&device));

    std.debug.print("Recording, press enter to stop\n", .{});

    _ = try stdin_reader.discardDelimiterInclusive('\n');
}

fn captureTestCb(
    pDevice: [*c]ma.ma_device,
    pOutput: ?*anyopaque,
    pInput: ?*const anyopaque,
    frameCount: ma.ma_uint32,
) callconv(.c) void {
    const count = frameCount * pDevice.*.capture.channels;
    const output: [*]f32 = @ptrCast(@alignCast(pOutput));
    const input_m: [*]const f32 = @ptrCast(@alignCast(pInput));
    const input = input_m[0..count];
    @memcpy(output, input);
}

fn duplex(stdin_reader: *std.Io.Reader) !void {
    var device_config = ma.ma_device_config_init(ma.ma_device_type_duplex);
    device_config.capture.pDeviceID = null; //capture_id;
    device_config.capture.format = ma.ma_format_f32;
    device_config.capture.channels = 2;
    device_config.capture.shareMode = ma.ma_share_mode_shared;
    device_config.playback.pDeviceID = null; //playback_id;
    device_config.playback.format = device_config.capture.format;
    device_config.playback.channels = device_config.capture.channels;
    device_config.playback.shareMode = ma.ma_share_mode_shared;
    device_config.sampleRate = 48000;
    device_config.dataCallback = captureTestCb;
    // device_config.pUserData = power;
    // device_config.noPreSilencedOutputBuffer = @intFromBool(true);

    var device: ma.ma_device = undefined;

    try ma_error_check(ma.ma_device_init(null, &device_config, &device));
    try ma_error_check(ma.ma_device_start(&device));

    std.debug.print("Press enter to stop\n", .{});
    _ = stdin_reader.discardDelimiterInclusive('\n') catch unreachable;
    ma.ma_device_uninit(&device);
}
