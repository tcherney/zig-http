//https://github.com/ikskuh/zig-network/blob/master/network.zig
const std = @import("std");

pub const TCPSocket = struct {
    address: std.net.Address,
    socket: std.posix.socket_t,

    pub fn init(ip: []const u8, port: u16) !TCPSocket {
        const parsed_address = try std.net.Address.parseIp4(ip, port);
        const sock: std.posix.socket_t = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0);
        errdefer std.posix.close(sock);
        return TCPSocket{ .address = parsed_address, .socket = sock };
    }

    pub fn bind(self: *const TCPSocket) !void {
        try std.posix.bind(self.socket, &self.address.any, self.address.getOsSockLen());
    }

    pub fn accept(self: *const TCPSocket) !TCPSocket {
        var addr: std.net.Address = undefined;
        var addr_size: std.posix.socklen_t = @sizeOf(std.net.Address);
        const add_ptr: *std.posix.sockaddr = @ptrCast(&addr);
        const client = try std.posix.accept(self.socket, add_ptr, &addr_size, 0);
        errdefer std.posix.close(client);
        return TCPSocket{
            .address = addr,
            .socket = client,
        };
    }
    pub fn listen(self: *const TCPSocket) !void {
        try std.posix.listen(self.socket, 0);
    }

    pub fn receive(self: *const TCPSocket, data: []u8) !usize {
        return try std.posix.recvfrom(self.socket, data, 0, null, null);
    }

    pub fn send(self: *const TCPSocket, data: []const u8) !usize {
        return try std.posix.send(self.socket, data, 0);
    }

    pub fn close(self: *const TCPSocket) void {
        std.posix.close(self.socket);
    }
};

test "echo" {
    const server = try TCPSocket.init("127.0.0.1", 8888);
    std.debug.print("{}", .{server});
    try server.bind();
    try server.listen();
    var buffer: [1024]u8 = undefined;
    while (true) {
        const client: TCPSocket = try server.accept();
        const bytes = try client.receive(&buffer);
        std.debug.print("received {d} bytes: {s}\n", .{ bytes, buffer });
        client.close();
        break;
    }
    server.close();
}
