# jolt-zig-vendor

Zig bindings to [Jolt Physics](https://github.com/jrouwe/JoltPhysics) 5.6.0 through [joltc](https://github.com/amerkoleci/joltc), with prebuilt static libraries. Unlike Jolt's default build, Jolt is built cross-platform deterministic (`JPH_CROSS_PLATFORM_DETERMINISTIC`), so results match across CPUs, operating systems and compilers. The `jolt` module holds the joltc API (`JPH_*`) and extensions (`JPHX_*`).

Fetch a [release](https://github.com/ali-shahwali/jolt-zig-vendor/releases) tag:

```sh
zig fetch --save=jolt https://github.com/ali-shahwali/jolt-zig-vendor/archive/refs/tags/<tag>.tar.gz
```

```zig
const jolt = b.dependency("jolt", .{ .target = target, .optimize = optimize }).module("jolt");
```

Prebuilt: `aarch64` and `x86_64` on `macos`, `linux-gnu` and `windows-gnu`, debug and fast. Another target fails to build, `-Dsource=true` (`.source = true` from a dependency) builds from source. The libraries link Zig 0.17.1 libc++, so use the same Zig version.
