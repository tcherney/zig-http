const std = @import("std");
const utils = @import("utils.zig");
pub const Endpoints: []const utils.Endpoint = &[2]utils.Endpoint{ utils.Endpoint{ .valid_requests = @intFromEnum(utils.Request.Request_Type.GET), .route = "/", .payload = utils.Endpoint.PayloadType{ .function = &home } }, utils.Endpoint{ .valid_requests = @intFromEnum(utils.Request.Request_Type.GET), .route = "/one", .payload = utils.Endpoint.PayloadType{ .function = &one } } };

pub fn home(_: utils.Endpoint.ArgParams) []const u8 {
    return "<html><body><h1>hello world</h1></body></html>";
}

pub fn one(_: utils.Endpoint.ArgParams) []const u8 {
    return "<html><body><h1>one</h1></body></html>";
}

test "zerver" {
    inline for (0..Endpoints.len) |i| {
        std.debug.print("{s}\n", .{Endpoints[i].payload.function(.{})});
    }
}
