const std = @import("std");
const io = std.io;
const mem = std.mem;
const Allocator = mem.Allocator;
const net = std.net;

const mcp = @import("mcp");
const mcio = mcp.packetio;
const mcv = mcp.vlatest;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const address = try net.Address.resolveIp("::", 25565);
    var server = try address.listen(.{ .reuse_port = true });

    defer server.deinit();
    std.log.info("Status server listening on {}", .{address});

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    while (true) {
        const conn = server.accept() catch |e| {
            std.log.err("Failed to accept connection: {any}", .{e});
            continue;
        };
        defer _ = arena.reset(.retain_capacity);
        handleClient(arena.allocator(), conn) catch |e| {
            std.log.err("Failed to handle client from {}, {any}", .{ conn.address, e });
            continue;
        };
    }
}
pub fn handleClient(a: Allocator, conn: net.Server.Connection) !void {
    defer conn.stream.close();
    var br = io.bufferedReader(conn.stream.reader());

    // Handshake state
    var handshake_packet =
        try mcio.readHandshakePacket(mcv.H.SB, br.reader(), .{ .allocator = a });
    defer mcv.H.SB.deinit(&handshake_packet, .{ .allocator = a });
    if (handshake_packet == .legacy) return;
    var bw = io.bufferedWriter(conn.stream.writer());
    if (handshake_packet.handshake.next_state == .login) {
        // Login state
        try mcio.writePacket(mcv.L.CB, bw.writer(), .{ .disconnect = 
        \\{"text":"This server does not support logging in."}
        }, .{});
        try bw.flush();
        return;
    }
    // Status state
    var request_packet = try mcio.readPacket(mcv.S.SB, br.reader(), .{ .allocator = a });
    defer mcv.S.SB.deinit(&request_packet, .{ .allocator = a });
    if (request_packet != .status_request) return;

    const response_data =
        \\{
        \\    "version": {
        \\        "name": "
    ++ mcv.MCVersion ++
        \\",
        \\        "protocol": 
    ++ std.fmt.comptimePrint("{}", .{mcv.ProtocolVersion}) ++
        \\    },
        \\    "players": {
        \\        "max": 32,
        \\        "online": 0
        \\    },
        \\    "description": {
        \\        "text": "Example status server"
        \\    }
        \\}
    ;

    try mcio.writePacket(
        mcv.S.CB,
        bw.writer(),
        .{ .status_response = response_data },
        .{},
    );
    try bw.flush();
    var stderr = std.io.getStdErr().writer();
    stderr.print("Sent status to {}", .{conn.address}) catch {};
    defer stderr.writeByte('\n') catch {};

    const time_sent = std.time.nanoTimestamp();

    var ping_packet = mcio.readPacket(
        mcv.S.SB,
        br.reader(),
        .{ .allocator = a },
    ) catch |e| {
        if (e == error.EndOfStream) return;
        return e;
    };
    defer mcv.S.SB.deinit(&ping_packet, .{ .allocator = a });
    if (ping_packet != .ping_request) return;
    const time_received = std.time.nanoTimestamp();
    try mcio.writePacket(mcv.S.CB, bw.writer(), .{
        .ping_response = ping_packet.ping_request,
    }, .{});
    try bw.flush();
    stderr.print(", ping {d:.3}ms", .{
        @as(f32, @floatFromInt(time_received - time_sent)) / std.time.ns_per_ms,
    }) catch {};
}
