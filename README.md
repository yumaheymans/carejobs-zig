# carejobs-zig

Zig client for the [CareJobs.Now](https://carejobs.now) healthcare jobs API. Search open US healthcare jobs, see the hourly pay employers post, and look up employers and states.

- Free, no API key.
- Standard library only (`std.http.Client`, `std.json`). Needs Zig 0.17.0 or newer (the `std.Io` interface).
- Typed results, one error set.
- The same API is a remote MCP server at <https://carejobs.now/api/mcp>, so any MCP client can use it too.

## Install

```sh
zig fetch --save git+https://github.com/yumaheymans/carejobs-zig
```

Then in your `build.zig`:

```zig
const carejobs = b.dependency("carejobs", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("carejobs", carejobs.module("carejobs"));
```

## Quick start

```zig
const std = @import("std");
const carejobs = @import("carejobs");

pub fn main(init: std.process.Init) !void {
    var client = carejobs.Client.init(init.gpa, init.io);

    const res = try client.searchJobs(.{ .query = "ICU", .kind = .nurses, .state = "TX", .limit = 5 });
    defer res.deinit();

    std.debug.print("{d} jobs match\n", .{res.value.total});
    for (res.value.jobs) |job| {
        std.debug.print("{s} | {s} | {s} | {s}\n", .{ job.title, job.employer, job.location orelse "", job.url });
    }

    const pay = try client.payByKind(.nurses);
    defer pay.deinit();
    if (pay.value.pay) |p| std.debug.print("Median posted pay for nurses: ${d}/hr\n", .{p.median});
}
```

Every result is a `std.json.Parsed(T)`: read it through `.value` and call `.deinit()` when you are done.

## Methods

| Method | What it answers | Result |
| --- | --- | --- |
| `Client.init(allocator, io)` | A client for the live API | `Client` |
| `searchJobs(params)` | Open jobs by query, kind, state and limit | `SearchResult` |
| `payByKind(kind)` | Posted hourly pay for one kind of job, and the employers posting the most | `PayResult` |
| `employers(query, limit)` | The employers, AI-training programs and job boards the site reads | `EmployerList` |
| `states()` | Open jobs in every US state | `StateList` |
| `carejobs.kinds` | The 17 kinds of job (no request) | `[]const Kind` |
| `callTool(T, name, arguments)` | Any tool of the server, decoded as `T` | `std.json.Parsed(T)` |

Every `SearchParams` field is optional (`null` leaves it off). `Kind` is an enum with the 17 kinds; `kind.slug()` is the string the API uses (`"nurse-practitioners"`) and `Kind.fromSlug("nurses")` reads one back.

Every `Job` carries `url`, its page on CareJobs.Now, where a person applies. The server has no separate job lookup by id: a job is described by the search answer.

Where the API sends `null`, the field is `null` (`Job.pay`, `SearchResult.pay`, `PayResult.pay`, and so on): `PayResult.pay` is null when too few jobs post an hourly rate to measure.

### Errors

A failed call returns an error from `carejobs.Error` (`HttpStatus`, `RpcError`, `ToolRefused`, `BadAnswer`) or one of the errors of `std.http.Client`. After a failure, `client.lastError()` has the server's message and `client.last_status` the HTTP status.

```zig
const res = client.searchJobs(.{ .state = "TX" }) catch |err| {
    std.debug.print("{s}: {s}\n", .{ @errorName(err), client.lastError() });
    return err;
};
```

The server answers a query it has not seen before in up to about 25 seconds (its database may be waking up), then repeats of it in a fraction of one, so a first call can be slow.

## Tests

```sh
zig build test    # offline, on answers recorded from the live API
zig build live    # the same calls against the real API
```

## Data

Data from [CareJobs.Now](https://carejobs.now), CC BY 4.0. Docs and downloads: <https://carejobs.now/data>.

## License

Code: MIT, copyright O-mega Enterprise, Inc. See [LICENSE](LICENSE).
