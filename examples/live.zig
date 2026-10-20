//! Asks the live API. Run with: zig build live
const std = @import("std");
const carejobs = @import("carejobs");

pub fn main(init: std.process.Init) !void {
    var client = carejobs.Client.init(init.gpa, init.io);

    const res = try client.searchJobs(.{ .query = "ICU", .kind = .nurses, .state = "TX", .limit = 3 });
    defer res.deinit();
    std.debug.print("{d} jobs match\n", .{res.value.total});
    for (res.value.jobs) |job| {
        std.debug.print("{s} | {s} | {s} | {s}\n", .{ job.title, job.employer, job.location orelse "", job.url });
    }

    const pay = try client.payByKind(.nurses);
    defer pay.deinit();
    if (pay.value.pay) |p| std.debug.print("Median posted pay for nurses: ${d}/hr\n", .{p.median});

    const employers = try client.employers("Kaiser", 3);
    defer employers.deinit();
    std.debug.print("{d} employers\n", .{employers.value.entries.len});

    const states = try client.states();
    defer states.deinit();
    std.debug.print("{d} states\n", .{states.value.states.len});
}
