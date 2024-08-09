const std = @import("std");
const tcp_socket = @import("tcp_socket.zig");

const NUM_THREADS: comptime_int = 50;

pub const HttpServer = struct {
    socket: tcp_socket.TCPSocket = undefined,
    thread_pool: *std.Thread.Pool = undefined,
    is_running: bool = true,
    allocator: std.mem.Allocator = undefined,
    endpoints: std.StringHashMap(Endpoint) = undefined,

    pub const Endpoint = struct {
        valid_requests: u9 = undefined,
        route: []const u8 = undefined,
    };

    pub const Request = struct {
        headers: std.StringHashMap([]const u8) = undefined,
        request_type: Request_Type = undefined,
        allocator: std.mem.Allocator = undefined,
        route: []const u8 = undefined,
        body: std.ArrayList(u8) = undefined,

        pub const Request_Type = enum(u9) {
            GET = 0x1,
            POST = 0x2,
            NOT_IMPLMENTED,
        };

        pub const Error = error{
            MALFORMED_REQUEST,
        };
        pub fn init(allocator: std.mem.Allocator) Request {
            return Request{ .allocator = allocator, .headers = std.StringHashMap([]const u8).init(allocator) };
        }

        pub fn deinit(self: *Request) void {
            self.headers.deinit();
            self.body.deinit();
        }

        pub fn parse(self: *Request, data: []u8) (std.mem.Allocator.Error || Error)!void {
            var lines: std.mem.SplitIterator(u8, std.mem.DelimiterType.any) = std.mem.splitAny(u8, data, "\n");
            //std.debug.print("parsing start line\n", .{});
            // parse start line
            var start_line_parts = std.mem.splitAny(u8, lines.next().?, " ");
            const request_type = start_line_parts.next().?;
            //std.debug.print("{s}\n", .{request_type});
            if (std.mem.eql(u8, request_type, "GET")) {
                self.request_type = Request_Type.GET;
            } else {
                self.request_type = Request_Type.NOT_IMPLMENTED;
            }
            self.route = start_line_parts.next().?;
            if (!std.mem.eql(u8, start_line_parts.next().?, "HTTP/1.1\r")) {
                return Error.MALFORMED_REQUEST;
            }
            //std.debug.print("parsing headers\n", .{});
            // parse headers
            var header = lines.next();
            while (header != null and header.?.len > 1) : (header = lines.next()) {
                //std.debug.print("parsing header {s}\n", .{header.?});
                //std.debug.print("with len {d}\n", .{header.?.len});
                const index = std.mem.indexOf(u8, header.?, ":").?;
                try self.headers.put(header.?[0..index], header.?[index + 1 ..]);
            }
            if (header == null) {
                return Error.MALFORMED_REQUEST;
            }
            // parse body
            else {
                //std.debug.print("parsing body\n", .{});
                self.body = std.ArrayList(u8).init(self.allocator);
                header = lines.next();
                while (header != null) : (header = lines.next()) {
                    _ = try self.body.writer().write(header.?);
                }
            }
            //std.debug.print("Request object {}\n", .{self});
        }
    };

    pub fn init(address: []const u8, port: u16, allocator: std.mem.Allocator) !HttpServer {
        var thread_pool: *std.Thread.Pool = try allocator.create(std.Thread.Pool);
        try thread_pool.init(.{ .allocator = allocator, .n_jobs = NUM_THREADS });
        return HttpServer{ .socket = try tcp_socket.TCPSocket.init(address, port), .thread_pool = thread_pool, .allocator = allocator, .endpoints = std.StringHashMap(Endpoint).init(allocator) };
    }

    pub fn add_endpoint(self: *HttpServer, route: []const u8, valid_requests: u9) !void {
        try self.endpoints.put(route, Endpoint{ .valid_requests = valid_requests, .route = route });
    }

    pub fn handle_request(self: *HttpServer, request: Request) !std.ArrayList(u8) {
        std.debug.print("request {s}, {}\n", .{ request.route, request.request_type });
        var response: std.ArrayList(u8) = std.ArrayList(u8).init(self.allocator);
        const endpoint = self.endpoints.get(request.route);
        // 404
        if (endpoint == null) {
            _ = try response.writer().write("HTTP/1.1 404 Not Found\r\n");
        }
        // 405
        else if (endpoint.?.valid_requests & @intFromEnum(request.request_type) == 0) {
            _ = try response.writer().write("HTTP/1.1 405 Method Not Allowed\r\n");
        }
        switch (request.request_type) {
            .GET => {
                var file_name: []const u8 = "index.html";
                if (!std.mem.eql(u8, request.route, "/")) {
                    file_name = request.route[1..];
                }
                const file = std.fs.cwd().openFile(file_name, .{}) catch {
                    // 404
                    _ = try response.writer().write("HTTP/1.1 404 Not Found\r\n");
                    return response;
                };
                defer file.close();
                const size_limit = std.math.maxInt(u32);
                const buffer = try file.readToEndAlloc(self.allocator, size_limit);
                _ = try response.writer().write("HTTP/1.1 200 OK\r\nServer: Zig Server\r\nContent-Type: text/html\r\n\r\n");
                _ = try response.writer().write(buffer);
                self.allocator.free(buffer);
            },
            .POST => {},
            .NOT_IMPLMENTED => {},
        }
        //_ = try response.writer().write("HTTP/1.1 200 OK\r\nServer: Zig Server\r\nContent-Type: text/html\r\n\r\n<html><body><h1>hello world</h1></body></html>");
        return response;
    }

    pub fn handle_client(self: *HttpServer, client: *tcp_socket.TCPSocket) void {
        defer self.deinit_client(client);
        var buffer: [1024]u8 = undefined;
        var bytes = client.receive(&buffer) catch {
            std.debug.print("Error receving data\n", .{});
            return;
        };
        //std.debug.print("received {d} bytes: {s}\n", .{ bytes, buffer });
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

    pub fn deinit_client(self: *HttpServer, client: *tcp_socket.TCPSocket) void {
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

test "echo" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var server = try HttpServer.init("127.0.0.1", 8888, allocator);
    try server.add_endpoint("/", @intFromEnum(HttpServer.Request.Request_Type.GET));
    try server.add_endpoint("/index.html", @intFromEnum(HttpServer.Request.Request_Type.GET));
    std.debug.print("{}", .{server});
    try server.start();
}
