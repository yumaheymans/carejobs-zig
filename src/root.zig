//! Client for the CareJobs.Now healthcare jobs API (https://carejobs.now).
//!
//! Search open US healthcare jobs, see the hourly pay employers post, and look
//! up employers and states. The API is free and needs no key. It is a remote
//! MCP server (https://carejobs.now/api/mcp); this package posts the JSON-RPC
//! calls for you and returns typed results. Standard library only.
//!
//! ```zig
//! const std = @import("std");
//! const carejobs = @import("carejobs");
//!
//! pub fn main(init: std.process.Init) !void {
//!     var client = carejobs.Client.init(init.gpa, init.io);
//!     const res = try client.searchJobs(.{ .query = "ICU", .kind = .nurses, .state = "TX", .limit = 5 });
//!     defer res.deinit();
//!     std.debug.print("{d} jobs match\n", .{res.value.total});
//!     for (res.value.jobs) |job| std.debug.print("{s} | {s} | {s}\n", .{ job.title, job.employer, job.url });
//! }
//! ```
//!
//! Data from CareJobs.Now (https://carejobs.now), CC BY 4.0.

const std = @import("std");

/// Version of this package, sent in the default User-Agent.
pub const version = "1.0.0";

/// The CareJobs.Now site. The MCP endpoint is this plus `/api/mcp`.
pub const default_base_url = "https://carejobs.now";

/// A kind of healthcare job, the `kind` filter of the API. `slug` is the string
/// the API uses, for example `"nurse-practitioners"`.
pub const Kind = enum {
    nurses,
    nurse_practitioners,
    physicians,
    nursing_assistants,
    caregivers,
    therapy_rehab,
    mental_health,
    pharmacy,
    imaging,
    lab,
    surgical_techs,
    emts_paramedics,
    medical_assistants,
    dental,
    admin,
    allied_health,
    ai_training,

    /// The slug the API uses for this kind.
    pub fn slug(self: Kind) []const u8 {
        return switch (self) {
            .nurses => "nurses",
            .nurse_practitioners => "nurse-practitioners",
            .physicians => "physicians",
            .nursing_assistants => "nursing-assistants",
            .caregivers => "caregivers",
            .therapy_rehab => "therapy-rehab",
            .mental_health => "mental-health",
            .pharmacy => "pharmacy",
            .imaging => "imaging",
            .lab => "lab",
            .surgical_techs => "surgical-techs",
            .emts_paramedics => "emts-paramedics",
            .medical_assistants => "medical-assistants",
            .dental => "dental",
            .admin => "admin",
            .allied_health => "allied-health",
            .ai_training => "ai-training",
        };
    }

    /// The kind with this API slug, or null.
    pub fn fromSlug(s: []const u8) ?Kind {
        for (kinds) |kind| {
            if (std.mem.eql(u8, kind.slug(), s)) return kind;
        }
        return null;
    }

    /// Writes the slug, so a `Kind` in the arguments becomes the string the API expects.
    pub fn jsonStringify(self: Kind, jws: anytype) !void {
        try jws.write(self.slug());
    }
};

/// All 17 kinds of job, in the order the API documents them.
pub const kinds = std.enums.values(Kind);

/// Filters of `Client.searchJobs`. Every field is optional and null leaves it off.
pub const SearchParams = struct {
    /// Words every job must carry in its title, place, department or schedule ("ICU", "night").
    query: ?[]const u8 = null,
    /// One kind of job.
    kind: ?Kind = null,
    /// A US state: its two-letter code ("TX") or its name ("Texas").
    state: ?[]const u8 = null,
    /// How many jobs to return, 1 to 25 (the server default is 10).
    limit: ?u8 = null,
};

/// One open job. `url` is its page on CareJobs.Now, where a person applies.
pub const Job = struct {
    title: []const u8,
    employer: []const u8,
    /// The job board the job was read through, when it is another employer's job.
    via: ?[]const u8 = null,
    /// The label of the kind of job, for example "Nurses".
    kind: []const u8,
    /// The posted pay as text, for example "$42.43-$86.19/hr". Null when the posting states none.
    pay: ?[]const u8 = null,
    schedule: []const []const u8 = &.{},
    facility: ?[]const u8 = null,
    location: ?[]const u8 = null,
    /// ISO date (YYYY-MM-DD) the job was first listed.
    listed: []const u8,
    url: []const u8,
    employer_page: ?[]const u8 = null,
};

/// Posted hourly pay in US dollars across the jobs a search matches.
pub const SearchPay = struct {
    typical_low: f64,
    typical_high: f64,
    median: f64,
    rate_samples: i64,
    /// How many matching jobs post an hourly rate.
    priced: i64,
    /// How many jobs match.
    open: i64,
};

/// The answer of `Client.searchJobs`.
pub const SearchResult = struct {
    /// Every open job that matches, not only the ones in `jobs`.
    total: i64,
    /// Null when no matching job posts a rate.
    pay: ?SearchPay = null,
    jobs: []const Job = &.{},
    /// The same search on the CareJobs.Now site.
    more: ?[]const u8 = null,
};

/// Posted hourly pay in US dollars, before shift differentials and bonuses.
pub const PayStats = struct {
    median: f64,
    typical_low: f64,
    typical_high: f64,
    rate_samples: i64,
    employers: i64,
    open_jobs: i64,
    no_rate: i64,
    /// True only where at least three employers post a rate.
    market_rate: bool,
};

/// The pay one employer posts for a kind of job.
pub const EmployerPay = struct {
    slug: []const u8,
    name: []const u8,
    median: f64,
    typical_low: f64,
    typical_high: f64,
    rate_samples: i64,
    employers: i64,
    open_jobs: i64,
    no_rate: i64,
    market_rate: bool,
};

/// The answer of `Client.payByKind`.
pub const PayResult = struct {
    /// ISO date the figures were measured.
    as_of: []const u8,
    kind: []const u8,
    open_jobs: i64,
    /// Null when too few jobs post an hourly rate to measure.
    pay: ?PayStats = null,
    /// The employers posting the most for this kind of job.
    best_paying: []const EmployerPay = &.{},
};

/// An employer, AI-training program or job board.
pub const Employer = struct {
    slug: []const u8,
    name: []const u8,
    /// "employer", "ai-program" or "job-board".
    type: []const u8,
    model: ?[]const u8 = null,
    care: ?[]const u8 = null,
    hq: ?[]const u8 = null,
    states: []const []const u8 = &.{},
    open_jobs: i64,
    posted_median_hourly: ?f64 = null,
    url: []const u8,
};

/// The answer of `Client.employers`.
pub const EmployerList = struct {
    /// Every match, not only the ones in `entries`.
    total: i64,
    entries: []const Employer = &.{},
};

/// The open jobs of one kind of job inside a state.
pub const KindCount = struct {
    kind: []const u8,
    label: []const u8,
    open_jobs: i64,
    url: ?[]const u8 = null,
};

/// One US state: open jobs, employers and the kinds of job it has the most of.
pub const StateSummary = struct {
    code: []const u8,
    name: []const u8,
    open_jobs: i64,
    employers: i64,
    top_kinds: []const KindCount = &.{},
    url: []const u8,
};

/// The answer of `Client.states`.
pub const StateList = struct {
    states: []const StateSummary = &.{},
};

/// Why a call failed. `Client.lastError` holds the server's message for
/// `HttpStatus`, `RpcError` and `ToolRefused`.
pub const Error = error{
    /// The server answered with a status other than 2xx.
    HttpStatus,
    /// The server answered with a JSON-RPC error.
    RpcError,
    /// The server ran the tool and refused (it reported `isError`).
    ToolRefused,
    /// The answer is not what MCP promises, or does not fit the result type.
    BadAnswer,
} || std.mem.Allocator.Error;

/// Calls the live API. Make one with `init`. A `Client` is not shared between
/// threads: make one per thread.
pub const Client = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    /// Another host than the CareJobs.Now site (a mirror or a test server), without a trailing slash.
    base_url: []const u8 = default_base_url,
    user_agent: []const u8 = "carejobs-zig/" ++ version,
    /// The HTTP status of the last answer, 0 before the first call.
    last_status: u16 = 0,
    error_buffer: [256]u8 = undefined,
    error_len: usize = 0,

    /// A client for the live API. `io` is the `std.Io` of your program (`init.io`
    /// in a `main(init: std.process.Init)`), `allocator` its allocator.
    pub fn init(allocator: std.mem.Allocator, io: std.Io) Client {
        return .{ .allocator = allocator, .io = io };
    }

    /// The server's message of the last failed call, or an empty string.
    pub fn lastError(self: *const Client) []const u8 {
        return self.error_buffer[0..self.error_len];
    }

    /// Search the open healthcare jobs. Call `deinit` on the result.
    pub fn searchJobs(self: *Client, params: SearchParams) !std.json.Parsed(SearchResult) {
        return self.callTool(SearchResult, "search_healthcare_jobs", params);
    }

    /// What open jobs of one kind post as hourly pay, and the employers posting
    /// the most for it. Call `deinit` on the result.
    pub fn payByKind(self: *Client, kind: Kind) !std.json.Parsed(PayResult) {
        return self.callTool(PayResult, "get_healthcare_pay", .{ .kind = kind });
    }

    /// The employers, AI-training programs and job boards CareJobs.Now reads,
    /// most open jobs first. `query` is part of a name ("Kaiser"), `limit` is 1
    /// to 100 (server default 20). Call `deinit` on the result.
    pub fn employers(self: *Client, query: ?[]const u8, limit: ?u8) !std.json.Parsed(EmployerList) {
        return self.callTool(EmployerList, "list_healthcare_employers", .{ .query = query, .limit = limit });
    }

    /// Open jobs for every US state, most first. Call `deinit` on the result.
    pub fn states(self: *Client) !std.json.Parsed(StateList) {
        return self.callTool(StateList, "get_healthcare_jobs_by_state", .{});
    }

    /// Run any tool and decode its `structuredContent` as `T`. The typed
    /// methods are built on it; use it for a tool or a field this package does
    /// not know yet (for example with `std.json.Value` as `T`).
    pub fn callTool(self: *Client, comptime T: type, tool: []const u8, arguments: anytype) !std.json.Parsed(T) {
        self.error_len = 0;
        self.last_status = 0;
        const payload = try requestBody(self.allocator, tool, arguments);
        defer self.allocator.free(payload);

        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/mcp", .{std.mem.trimEnd(u8, self.base_url, "/")});
        defer self.allocator.free(url);

        var http_client: std.http.Client = .{ .allocator = self.allocator, .io = self.io };
        defer http_client.deinit();

        var body: std.Io.Writer.Allocating = .init(self.allocator);
        defer body.deinit();

        const result = http_client.fetch(.{
            .location = .{ .url = url },
            .method = .POST,
            .payload = payload,
            .headers = .{
                .content_type = .{ .override = "application/json" },
                .user_agent = .{ .override = self.user_agent },
            },
            .extra_headers = &.{.{ .name = "Accept", .value = "application/json" }},
            .response_writer = &body.writer,
        }) catch |err| {
            self.setError(@errorName(err));
            return err;
        };
        self.last_status = @backingInt(result.status);

        const text = body.written();
        if (@backingInt(result.status) < 200 or @backingInt(result.status) > 299) {
            if (!self.setRpcError(text)) self.setError(std.mem.trim(u8, text, " \r\n\t"));
            return error.HttpStatus;
        }
        return self.decode(T, text);
    }

    fn decode(self: *Client, comptime T: type, text: []const u8) !std.json.Parsed(T) {
        const parsed = std.json.parseFromSlice(Envelope(T), self.allocator, text, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch {
            self.setError("the server did not answer with the expected JSON-RPC message");
            return error.BadAnswer;
        };
        errdefer parsed.deinit();
        const envelope = parsed.value;
        if (envelope.@"error") |rpc_error| {
            self.setError(rpc_error.message orelse "JSON-RPC error");
            return error.RpcError;
        }
        const res = envelope.result orelse {
            self.setError("the answer held no result");
            return error.BadAnswer;
        };
        if (res.isError) {
            for (res.content) |part| {
                if (part.text) |t| {
                    self.setError(t);
                    break;
                }
            }
            return error.ToolRefused;
        }
        const structured = res.structuredContent orelse {
            self.setError("the tool answered without structured content");
            return error.BadAnswer;
        };
        return .{ .arena = parsed.arena, .value = structured };
    }

    /// Keeps the message of a JSON-RPC error body. False for a body that is not one.
    fn setRpcError(self: *Client, text: []const u8) bool {
        const parsed = std.json.parseFromSlice(Envelope(std.json.Value), self.allocator, text, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch return false;
        defer parsed.deinit();
        const rpc_error = parsed.value.@"error" orelse return false;
        self.setError(rpc_error.message orelse "JSON-RPC error");
        return true;
    }

    fn setError(self: *Client, message: []const u8) void {
        const n = @min(message.len, self.error_buffer.len);
        @memcpy(self.error_buffer[0..n], message[0..n]);
        self.error_len = n;
    }
};

fn Envelope(comptime T: type) type {
    return struct {
        result: ?struct {
            content: []const struct { text: ?[]const u8 = null } = &.{},
            structuredContent: ?T = null,
            isError: bool = false,
        } = null,
        @"error": ?struct {
            code: ?i64 = null,
            message: ?[]const u8 = null,
        } = null,
    };
}

/// The JSON-RPC `tools/call` request for `tool`. Caller owns the returned memory.
pub fn requestBody(allocator: std.mem.Allocator, tool: []const u8, arguments: anytype) std.mem.Allocator.Error![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .jsonrpc = "2.0",
        .id = 1,
        .method = "tools/call",
        .params = .{ .name = tool, .arguments = arguments },
    }, .{ .emit_null_optional_fields = false });
}

const testing = std.testing;

fn parseFixture(comptime T: type, comptime text: []const u8) !std.json.Parsed(T) {
    return std.json.parseFromSlice(T, testing.allocator, text, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
}

test "there are 17 kinds with the API slugs" {
    try testing.expectEqual(@as(usize, 17), kinds.len);
    try testing.expectEqualStrings("nurse-practitioners", Kind.nurse_practitioners.slug());
    try testing.expectEqualStrings("emts-paramedics", Kind.emts_paramedics.slug());
    try testing.expectEqual(Kind.therapy_rehab, Kind.fromSlug("therapy-rehab").?);
    try testing.expect(Kind.fromSlug("nope") == null);
}

test "request body leaves unset filters out and writes kind as its slug" {
    const body = try requestBody(testing.allocator, "search_healthcare_jobs", SearchParams{ .state = "TX", .kind = .nurse_practitioners, .limit = 3 });
    defer testing.allocator.free(body);
    try testing.expectEqualStrings(
        \\{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search_healthcare_jobs","arguments":{"kind":"nurse-practitioners","state":"TX","limit":3}}}
    , body);
}

test "search answer recorded from the live API" {
    const parsed = try parseFixture(SearchResult, @embedFile("testdata/search.json"));
    defer parsed.deinit();
    const r = parsed.value;
    try testing.expect(r.total >= 2);
    try testing.expectEqual(@as(usize, 2), r.jobs.len);
    try testing.expectEqualStrings("Nurses", r.jobs[0].kind);
    try testing.expect(r.jobs[0].via == null);
    try testing.expectEqual(@as(f64, 45), r.pay.?.median);
}

test "pay answer recorded from the live API" {
    const parsed = try parseFixture(PayResult, @embedFile("testdata/pay.json"));
    defer parsed.deinit();
    const r = parsed.value;
    try testing.expectEqualStrings("nurses", r.kind);
    try testing.expectEqual(@as(f64, 45), r.pay.?.median);
    try testing.expect(r.pay.?.market_rate);
    try testing.expectEqual(@as(usize, 2), r.best_paying.len);
}

test "employers answer recorded from the live API" {
    const parsed = try parseFixture(EmployerList, @embedFile("testdata/employers.json"));
    defer parsed.deinit();
    const r = parsed.value;
    try testing.expectEqual(@as(usize, 2), r.entries.len);
    try testing.expectEqualStrings("cross-country-healthcare", r.entries[0].slug);
    try testing.expectEqualStrings("employer", r.entries[0].type);
    try testing.expect(r.entries[0].posted_median_hourly == null);
}

test "states answer recorded from the live API" {
    const parsed = try parseFixture(StateList, @embedFile("testdata/states.json"));
    defer parsed.deinit();
    const r = parsed.value;
    try testing.expectEqualStrings("TX", r.states[0].code);
    try testing.expectEqual(@as(usize, 3), r.states[0].top_kinds.len);
}

test "a tool the server refuses raises ToolRefused with its text" {
    var client: Client = .{ .allocator = testing.allocator, .io = undefined };
    const text =
        \\{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"kind needs a state"}],"isError":true}}
    ;
    try testing.expectError(error.ToolRefused, client.decode(SearchResult, text));
    try testing.expectEqualStrings("kind needs a state", client.lastError());
}

test "a JSON-RPC error raises RpcError with its message" {
    var client: Client = .{ .allocator = testing.allocator, .io = undefined };
    const text =
        \\{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"Unknown tool"}}
    ;
    try testing.expectError(error.RpcError, client.decode(SearchResult, text));
    try testing.expectEqualStrings("Unknown tool", client.lastError());
    try testing.expect(client.setRpcError(text));
}

test "an answer with structured content decodes" {
    var client: Client = .{ .allocator = testing.allocator, .io = undefined };
    const text =
        \\{"jsonrpc":"2.0","id":1,"result":{"content":[],"structuredContent":{"total":7,"jobs":[]}}}
    ;
    const parsed = try client.decode(SearchResult, text);
    defer parsed.deinit();
    try testing.expectEqual(@as(i64, 7), parsed.value.total);
}
