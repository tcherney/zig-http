const std = @import("std");

pub const Endpoint = struct {
    valid_requests: u9 = undefined,
    route: []const u8 = undefined,
    as_page: bool = false,
    payload: PayloadType = undefined,
    pub const ArgParams = struct {
        params: [][]const u8 = undefined,
        buffer: []u8 = undefined,
        allocator: std.mem.Allocator = undefined,
    };
    pub const PayloadType = union {
        file_name: []const u8,
        function: *const fn (ArgParams) ?[]u8,
    };
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
            const index = std.mem.indexOf(u8, header.?, " ").?;
            //std.debug.print("{s} key\r\n", .{header.?[0 .. index - 1]});
            //std.debug.print("{s}\r\n", .{header.?[index + 1 ..]});
            try self.headers.put(header.?[0 .. index - 1], header.?[index + 1 ..]);
        }
        // parse body
        if (header != null) {
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
