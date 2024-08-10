const std = @import("std");
const utils = @import("utils.zig");
pub const Endpoints: []const utils.Endpoint = &[2]utils.Endpoint{ utils.Endpoint{ .valid_requests = @intFromEnum(utils.Request.Request_Type.GET), .route = "/", .payload = utils.Endpoint.PayloadType{ .function = &home } }, utils.Endpoint{ .valid_requests = @intFromEnum(utils.Request.Request_Type.GET), .route = "/one", .payload = utils.Endpoint.PayloadType{ .function = &one } } };
pub var counter: u32 = 0;

pub fn home(args: utils.Endpoint.ArgParams) ?[]u8 {
    return std.fmt.allocPrint(args.allocator, "<html><body><h1>hello world</h1></body></html>", .{}) catch {
        return null;
    };
}

pub fn one(args: utils.Endpoint.ArgParams) ?[]u8 {
    counter += 1;
    return std.fmt.allocPrint(args.allocator, "<html><body><h1>{d}</h1></body></html>", .{counter}) catch {
        return null;
    };
}

test "zerver" {
    inline for (0..Endpoints.len) |i| {
        std.debug.print("{s}\n", .{Endpoints[i].payload.function(.{}).?});
    }
}
