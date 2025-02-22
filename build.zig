const std = @import("std");

fn createYamlModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const yaml = b.dependency("yaml", .{
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("yaml", yaml.module("yaml"));
    return mod;
}

pub fn build(b: *std.Build) !void {
    const hostTarget = b.standardTargetOptions(.{});
    const windowsQuery = try std.Target.Query.parse(.{ .arch_os_abi = "x86-windows-gnu" });
    const windowsTarget = b.resolveTargetQuery(windowsQuery);
    const optimize = b.standardOptimizeOption(.{});

    const yaml = b.dependency("yaml", .{
        .target = hostTarget,
        .optimize = optimize,
    });
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = hostTarget,
        .optimize = optimize,
    });
    exe_mod.addImport("yaml", yaml.module("yaml"));

    const exe = b.addExecutable(.{
        .name = "yaml",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run yaml configurator");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_module = createYamlModule(b, hostTarget, optimize),
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    const lldb = b.addSystemCommand(&.{
        "lldb",
        // add lldb flags before --
        "--",
    });
    lldb.addArtifactArg(lib_unit_tests);
    const lldb_step = b.step("debug", "run the tests under lldb");
    lldb_step.dependOn(&lldb.step);

    const plugin_mod = b.createModule(.{
        .target = windowsTarget,
        .optimize = optimize,
        .link_libc = true,
    });

    plugin_mod.addIncludePath(b.path("include"));

    plugin_mod.addCSourceFile(.{
        .file = b.path("src/entry.c"),
    });
    plugin_mod.addCSourceFile(.{
        .file = b.path("src/pluginapi.c"),
    });
    plugin_mod.addCMacro("UNICODE", "1");

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "yaml",
        .root_module = createYamlModule(b, windowsTarget, optimize),
        .use_lld = true,
    });
    plugin_mod.linkLibrary(lib);

    const plugin = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "nsYaml",
        .root_module = plugin_mod,
    });

    const plugin_step = b.step("plugin", "Create nsis plugin");
    const pluginInstall = b.addInstallArtifact(plugin, .{});
    plugin_step.dependOn(&pluginInstall.step);
}
