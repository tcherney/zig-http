const std = @import("std");
const tcp_socket = @import("tcp_socket.zig");
const utils = @import("utils.zig");
const zerver = @import("zerver.zig");
pub const Endpoint = utils.Endpoint;
pub const Request = utils.Request;

const NUM_THREADS: comptime_int = 50;

pub const HttpServer = struct {
    socket: tcp_socket.TCPSocket = undefined,
    address: []const u8 = undefined,
    thread_pool: *std.Thread.Pool = undefined,
    is_running: bool = true,
    allocator: std.mem.Allocator = undefined,
    endpoints: std.StringHashMap(Endpoint) = undefined,
    using_zerver: bool = false,

    pub fn init(address: []const u8, port: u16, allocator: std.mem.Allocator) !HttpServer {
        var thread_pool: *std.Thread.Pool = try allocator.create(std.Thread.Pool);
        try thread_pool.init(.{ .allocator = allocator, .n_jobs = NUM_THREADS });
        return HttpServer{ .socket = try tcp_socket.TCPSocket.init(address, port), .thread_pool = thread_pool, .allocator = allocator, .endpoints = std.StringHashMap(Endpoint).init(allocator), .address = address };
    }

    pub fn add_endpoint(self: *HttpServer, route: []const u8, payload: []const u8, valid_requests: u9) !void {
        try self.endpoints.put(route, Endpoint{ .valid_requests = valid_requests, .route = route, .file_name = payload, .as_page = true });
    }

    pub fn use_zerver(self: *HttpServer) !void {
        self.using_zerver = true;
        inline for (0..zerver.Endpoints.len) |i| {
            try self.endpoints.put(zerver.Endpoints[i].route, Endpoint{ .valid_requests = @intFromEnum(Request.Request_Type.GET), .route = zerver.Endpoints[i].route, .payload = zerver.Endpoints[i].payload, .as_page = false });
        }
    }

    fn response_code(_: *HttpServer, code: u16) []const u8 {
        switch (code) {
            200 => return "HTTP/1.1 200 OK\r\n",
            400 => return "HTTP/1.1 400 Bad Request\r\n",
            401 => return "HTTP/1.1 401 Unauthorized\r\n",
            403 => return "HTTP/1.1 403 Forbidden\r\n",
            404 => return "HTTP/1.1 404 Not Found\r\n",
            405 => return "HTTP/1.1 405 Method Not Allowed\r\n",
            429 => return "HTTP/1.1 429 Too Many Requests\r\n",
            500 => return "HTTP/1.1 500 Internal Server Error\r\n",
            501 => return "HTTP/1.1 501 Not Implemented\r\n",
            502 => return "HTTP/1.1 502 Bad Gateway\r\n",
            else => return "HTTP/1.1 500 Internal Server Error\r\n",
        }
    }

    fn handle_request(self: *HttpServer, request: Request) !std.ArrayList(u8) {
        std.debug.print("request {s}, {}\n", .{ request.route, request.request_type });
        var response: std.ArrayList(u8) = std.ArrayList(u8).init(self.allocator);
        var absolute = false;
        // std.debug.print("{s} {d}\n", .{ self.address, self.address.len });
        // std.debug.print("\n", .{});
        // std.debug.print("{s} {d}\n", .{ request.headers.get("Host").?, request.headers.get("Host").?.len });
        if (request.route[0] != '/') {
            if (std.mem.containsAtLeast(u8, self.address, 1, request.route)) {
                absolute = true;
            }
        }
        const endpoint = if (absolute) self.endpoints.get(request.route[request.headers.get("Host").?.len..]) else self.endpoints.get(request.route);
        // 404
        if (endpoint == null) {
            _ = try response.writer().write(self.response_code(404));
        }
        // 405
        else if (endpoint.?.valid_requests & @intFromEnum(request.request_type) == 0) {
            _ = try response.writer().write(self.response_code(405));
        } else switch (request.request_type) {
            .GET => {
                if (endpoint.?.as_page) {
                    const file = std.fs.cwd().openFile(endpoint.?.payload.file_name, .{}) catch {
                        // 404
                        _ = try response.writer().write(self.response_code(404));
                        return response;
                    };
                    defer file.close();
                    const size_limit = std.math.maxInt(u32);
                    const buffer = try file.readToEndAlloc(self.allocator, size_limit);
                    _ = try response.writer().write(self.response_code(200));
                    _ = try response.writer().write("Server: Zig Server\r\nContent-Type: text/html\r\n\r\n");
                    _ = try response.writer().write(buffer);
                    self.allocator.free(buffer);
                } else if (self.using_zerver) {
                    _ = try response.writer().write(self.response_code(200));
                    _ = try response.writer().write("Server: Zig Server\r\nContent-Type: text/html\r\n\r\n");
                    const payload_res: ?[]u8 = endpoint.?.payload.function(.{ .allocator = self.allocator });
                    if (payload_res != null) {
                        _ = try response.writer().write(payload_res.?);
                        self.allocator.free(payload_res.?);
                    } else {
                        _ = try response.writer().write(self.response_code(500));
                    }
                } else {
                    _ = try response.writer().write(self.response_code(500));
                }
            },
            .POST => {
                _ = try response.writer().write(self.response_code(501));
            },
            .NOT_IMPLMENTED => {
                _ = try response.writer().write(self.response_code(501));
            },
        }
        //_ = try response.writer().write("HTTP/1.1 200 OK\r\nServer: Zig Server\r\nContent-Type: text/html\r\n\r\n<html><body><h1>hello world</h1></body></html>");
        return response;
    }

    fn handle_client(self: *HttpServer, client: *tcp_socket.TCPSocket) void {
        defer self.deinit_client(client);
        var buffer: [1024]u8 = undefined;
        var bytes = client.receive(&buffer) catch {
            std.debug.print("Error receving data\n", .{});
            return;
        };
        std.debug.print("received {d} bytes: {s}\n", .{ bytes, buffer });
        if (bytes > 0) {
            var request: Request = Request.init(self.allocator);
            request.parse(&buffer) catch |err| {
                std.debug.print("Error parsing request {}\n", .{err});
                return;
            };
            const response = self.handle_request(request);
            if (response) |value| {
                bytes = client.send(value.items) catch {
                    std.debug.print("Error sending data\n", .{});
                    return;
                };
                std.debug.print("sent {d} bytes {s}\n", .{ bytes, value.items });
                value.deinit();
            } else |err| {
                std.debug.print("Error handling request {}\n", .{err});
            }
        }
    }

    fn deinit_client(self: *HttpServer, client: *tcp_socket.TCPSocket) void {
        client.close();
        self.allocator.destroy(client);
    }

    pub fn deinit(self: *HttpServer) !void {
        self.is_running = false;
        self.thread_pool.deinit();
        self.socket.close();
        self.allocator.destroy(self.thread_pool);
        self.endpoints.deinit();
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

// test "static" {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     const allocator = gpa.allocator();
//     var server = try HttpServer.init("127.0.0.1", 8888, allocator);
//     try server.add_endpoint("/", "index.html", @intFromEnum(Request.Request_Type.GET));
//     std.debug.print("{}", .{server});
//     try server.start();
// }

test "framework" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var server = try HttpServer.init("127.0.0.1", 8888, allocator);
    try server.use_zerver();
    //std.debug.print("{}", .{server});
    try server.start();
}
