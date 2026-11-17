//! Exposes JoltPhysics, joltc (C API) and its extensions (JPHX_*) to Zig as the `jolt` module (translate-c).
//! The static library comes prebuilt from this repository's releases. It builds from source only with `-Dsource`.

const std = @import("std");
const Translator = @import("translate_c").Translator;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const source = b.option(bool, "source", "Build Jolt from source instead of using a prebuilt library (default: false)") orelse false;

    const translate_c = b.dependency("translate_c", .{});
    var t: Translator = undefined;
    if (source) {
        const lib = buildLibrary(b, target, optimize) orelse return;
        b.installArtifact(lib);
        t = .init(translate_c, .{
            .name = "jolt",
            .c_source_file = b.path("src/jolt_ext.h"),
            .target = target,
            .optimize = optimize,
        });
        t.linkLibrary(lib);
    } else if (prebuiltName(b, target, optimize)) |name| {
        const prebuilt = b.lazyDependency(name, .{}) orelse return;
        // The header comes from the same release as the library, so the bindings match the binary.
        t = .init(translate_c, .{
            .name = "jolt",
            .c_source_file = prebuilt.path("include/jolt_ext.h"),
            .target = target,
            .optimize = optimize,
        });
        t.addIncludePath(prebuilt.path("include"));
        const result = target.result;
        t.mod.addObjectFile(prebuilt.path(b.fmt("lib/{s}joltc{s}", .{ result.libPrefix(), result.staticLibSuffix() })));
        t.mod.link_libcpp = true;
    } else {
        // Configure still succeeds, so steps that do not use the module keep working.
        const fail = b.addFail(b.fmt(
            "no prebuilt Jolt library for {s} {s}: run the Release workflow, or build from source with `-Dsource=true` (`.source = true` from a dependent package)",
            .{ b.fmt("{t}-{t}-{t}", .{ target.result.cpu.arch, target.result.os.tag, target.result.abi }), @tagName(optimize) },
        ));
        t = .init(translate_c, .{
            .name = "jolt",
            .c_source_file = b.path("src/jolt_ext.h"),
            .target = target,
            .optimize = optimize,
        });
        t.run.step.dependOn(&fail.step);
    }
    for (abi_defines) |d| t.defineCMacro(d[0], d[1]);
    b.modules.put(b.graph.arena, "jolt", t.mod) catch @panic("OOM");

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/jolt_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "jolt", .module = t.mod }},
        }),
    });
    const test_step = b.step("test", "Check that the bindings link and run");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}

/// These defines change Jolt's ABI, so the same set is used for Jolt, joltc and translate-c.
/// Cross-platform determinism gives the same results on every CPU, OS and compiler, for client prediction.
const abi_defines = [_][2][]const u8{
    // joltc requires 32-bit object layers (see OBJECT_LAYER_BITS in its CMakeLists).
    .{ "JPH_OBJECT_LAYER_BITS", "32" },
    .{ "JPH_CROSS_PLATFORM_DETERMINISTIC", "1" },
};

/// The name of the prebuilt library package for this configuration, or null when no release holds one.
/// Releases hold one Debug and one ReleaseFast library for each target.
fn prebuiltName(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) ?[]const u8 {
    const result = target.result;
    switch (result.os.tag) {
        .macos => {},
        .linux, .windows => if (result.abi != .gnu) return null,
        else => return null,
    }
    const mode = switch (optimize) {
        .debug => "debug",
        .safe, .fast, .small => "release",
    };
    const name = b.fmt("prebuilt_{s}_{s}_{s}", .{ @tagName(result.cpu.arch), @tagName(result.os.tag), mode });
    // The release workflow writes these packages into build.zig.zon. Before the first release there are none.
    for (b.available_deps) |dep| {
        if (std.mem.eql(u8, dep[0], name)) return name;
    }
    return null;
}

/// Builds JoltPhysics, joltc and the extensions as one static library. Null until the sources are fetched.
fn buildLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) ?*std.Build.Step.Compile {
    const jolt = b.lazyDependency("jolt", .{});
    const joltc = b.lazyDependency("joltc", .{});
    if (jolt == null) return null;
    if (joltc == null) return null;

    const lib = b.addLibrary(.{
        .name = "joltc",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });
    const mod = lib.root_module;
    mod.addIncludePath(jolt.?.path(""));
    mod.addIncludePath(joltc.?.path("include"));

    for (abi_defines) |d| mod.addCMacro(d[0], d[1]);
    if (optimize == .debug) mod.addCMacro("JPH_ENABLE_ASSERTS", "1") else mod.addCMacro("NDEBUG", "1");

    const flags: []const []const u8 = &.{
        "-std=c++17",
        "-fno-rtti",
        // Jolt relies on precise IEEE math for determinism; keep FMA contraction off like CMake does.
        "-ffp-contract=off",
        "-fno-sanitize=undefined",
    };

    const sources = collectJoltSources(b, jolt.?) catch |err| std.debug.panic("cannot list Jolt sources: {t}", .{err});
    mod.addCSourceFiles(.{ .root = jolt.?.path("Jolt"), .files = sources, .flags = flags });
    mod.addCSourceFiles(.{ .root = joltc.?.path("src"), .files = &.{ "joltc.cpp", "joltc_assert.cpp" }, .flags = flags });
    // The extensions: Jolt features that joltc does not expose.
    mod.addIncludePath(b.path("src"));
    mod.addCSourceFiles(.{ .root = b.path("src"), .files = &.{"jolt_ext.cpp"}, .flags = flags });

    lib.installHeader(joltc.?.path("include/joltc.h"), "joltc.h");
    lib.installHeader(b.path("src/jolt_ext.h"), "jolt_ext.h");
    return lib;
}

/// Every .cpp under Jolt/, except the GPU compute backends and their shader wrappers which need
/// precompiled HLSL (Jolt only uses them for hair simulation, which this package does not enable).
fn collectJoltSources(b: *std.Build, jolt: *std.Build.Dependency) ![]const []const u8 {
    const io = b.graph.io;
    const root = jolt.builder.root.root_dir.handle;
    var dir = try root.openDir(io, "Jolt", .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(b.allocator);
    defer walker.deinit();

    var files: std.ArrayList([]const u8) = .empty;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".cpp")) continue;
        const path = entry.path;
        const excluded = [_][]const u8{ "Compute/CPU/", "Compute/DX12/", "Compute/VK/", "Compute/MTL/", "Shaders/" };
        var skip = false;
        for (excluded) |prefix| {
            if (std.mem.startsWith(u8, path, prefix)) skip = true;
        }
        if (skip) continue;
        // Normalize Windows separators so the list is stable across hosts.
        const normalized = try b.allocator.dupe(u8, path);
        std.mem.replaceScalar(u8, normalized, '\\', '/');
        try files.append(b.allocator, normalized);
    }
    std.mem.sort([]const u8, files.items, {}, lessThan);
    return files.items;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
