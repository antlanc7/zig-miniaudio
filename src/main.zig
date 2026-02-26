const std = @import("std");
const ma = @cImport(@cInclude("miniaudio.h"));

fn ma_error_check(result: ma.ma_result) !void {
    if (result != ma.MA_SUCCESS) {
        std.log.err("{}", .{result});
        return error.MiniAudioError;
    }
}

export fn capture_callback(
    pDevice: [*c]ma.ma_device,
    pOutput: ?*anyopaque,
    pInput: ?*const anyopaque,
    frameCount: ma.ma_uint32,
) callconv(.c) void {
    _ = pOutput;
    const count = frameCount * pDevice.*.capture.channels;
    const input_m: [*]const f32 = @ptrCast(@alignCast(pInput));
    const input = input_m[0..count];
    std.log.debug("pitch: {}", .{computePitch(input)});
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

    var device_config = ma.ma_device_config_init(ma.ma_device_type_capture);
    device_config.capture.pDeviceID = &pCaptureDeviceInfos[index].id;
    device_config.capture.format = ma.ma_format_f32;
    device_config.capture.channels = 2;
    device_config.sampleRate = 44100;
    device_config.dataCallback = capture_callback;
    device_config.pUserData = null;

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

fn computePitch(samples: []const f32) f32 {
    const MIN_FREQ = 50.0;
    const MAX_FREQ = 1000.0;
    const SAMPLE_RATE = 48000;

    const min_lag: usize = @intFromFloat(SAMPLE_RATE / MAX_FREQ);
    const max_lag: usize = @intFromFloat(SAMPLE_RATE / MIN_FREQ);

    var best_lag: usize = 0;
    var min_diff: f32 = std.math.inf(f32);

    // Difference function (YIN simplified)
    var lag = min_lag;
    while (lag < max_lag and lag < samples.len) : (lag += 1) {
        var diff: f32 = 0;
        var i: usize = 0;
        while (i < samples.len - lag) : (i += 1) {
            const delta = samples[i] - samples[i + lag];
            diff += delta * delta;
        }

        if (diff < min_diff) {
            min_diff = diff;
            best_lag = lag;
        }
    }

    if (best_lag == 0) return 0;
    return SAMPLE_RATE / @as(f32, @floatFromInt(best_lag));
}
