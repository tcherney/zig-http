const std = @import("std");
const tcp_socket = @import("tcp_socket.zig");

const NUM_THREADS: comptime_int = 50;

pub const HttpServer = struct {
    socket: tcp_socket.TCPSocket = undefined,
    thread_pool: *std.Thread.Pool = undefined,
    is_running: bool = true,
    allocator: std.mem.Allocator = undefined,

    pub fn init(address: []const u8, port: u16, allocator: std.mem.Allocator) !HttpServer {
        var thread_pool: *std.Thread.Pool = try allocator.create(std.Thread.Pool);
        try thread_pool.init(.{ .allocator = allocator, .n_jobs = NUM_THREADS });
        return HttpServer{ .socket = try tcp_socket.TCPSocket.init(address, port), .thread_pool = thread_pool, .allocator = allocator };
    }

    pub fn handle_request(_: *HttpServer) []const u8 {
        return "HTTP/1.1 200 OK\r\nServer: Zig Server\r\nContent-Type: text/html\r\n\r\n<html><body><h1>hello world</h1></body></html>";
    }
    pub fn handle_client(self: *HttpServer, client: *tcp_socket.TCPSocket) void {
        defer self.deinit_client(client);
        var buffer: [1024]u8 = undefined;
        var bytes = client.receive(&buffer) catch {
            std.debug.print("Error recieving data\n", .{});
            return;
        };
        std.debug.print("received {d} bytes: {s}\n", .{ bytes, buffer });
        const response = self.handle_request();
        bytes = client.send(response) catch {
            std.debug.print("Error sending data\n", .{});
            return;
        };
        std.debug.print("sent {d} bytes {s}\n", .{ bytes, response });
    }

    pub fn deinit_client(self: *HttpServer, client: *tcp_socket.TCPSocket) void {
        client.close();
        self.allocator.destroy(client);
    }

    pub fn deinit(self: *HttpServer) !void {
        self.is_running = false;
        self.thread_pool.deinit();
        self.socket.close();
        self.allocator.destroy(self.thread_pool);
    }

    pub fn start(self: *HttpServer) !void {
        try self.socket.bind();
        try self.socket.listen();
        while (self.is_running) {
            const client: *tcp_socket.TCPSocket = try self.allocator.create(tcp_socket.TCPSocket);
            client.* = try self.socket.accept();
            try self.thread_pool.spawn(handle_client, .{ self, client });
        }
        self.socket.close();
    }
};

test "echo" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var server = try HttpServer.init("127.0.0.1", 8888, allocator);
    std.debug.print("{}", .{server});
    try server.start();
}
