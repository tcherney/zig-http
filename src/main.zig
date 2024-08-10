//https://datatracker.ietf.org/doc/html/rfc9112
const std = @import("std");
const http_server = @import("http_server.zig");

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const argsv = try std.process.argsAlloc(allocator);
    var server: http_server.HttpServer = undefined;
    if (argsv.len > 1) {
        if (argsv.len < 3) {
            try stdout.print("Usage: {s} ip4_address port\n", .{argsv[0]});
            try bw.flush();
            return;
        }
        const port = std.fmt.parseInt(u16, argsv[2], 10) catch {
            try stdout.print("Usage: {s} ip4_address port\n", .{argsv[0]});
            try bw.flush();
            return;
        };
        server = try http_server.HttpServer.init(argsv[1], port, allocator);
    } else {
        server = try http_server.HttpServer.init("127.0.0.1", 8888, allocator);
    }
    std.process.argsFree(allocator, argsv);
    try server.use_zerver();
    try server.start();
    _ = gpa.deinit();
}
