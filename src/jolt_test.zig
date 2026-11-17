//! Checks that the `jolt` module links and runs: Jolt starts, and joltc and JPHX calls work.

const std = @import("std");
const jolt = @import("jolt");

test "Jolt starts, makes a shape and a JPHX material, and shuts down" {
    try std.testing.expect(jolt.JPH_Init());
    defer jolt.JPH_Shutdown();

    const shape = jolt.JPH_SphereShape_Create(0.5) orelse return error.ShapeCreateFailed;
    defer jolt.JPH_Shape_Destroy(@ptrCast(shape));

    const material = jolt.JPHX_PhysicsMaterial_Create(7, 0.5, 0.25) orelse return error.MaterialCreateFailed;
    defer jolt.JPH_PhysicsMaterial_Destroy(material);
    try std.testing.expectEqual(@as(u32, 7), jolt.JPHX_PhysicsMaterial_GetIndex(material));
    try std.testing.expectEqual(@as(f32, 0.5), jolt.JPHX_PhysicsMaterial_GetFriction(material));
    try std.testing.expectEqual(@as(f32, 0.25), jolt.JPHX_PhysicsMaterial_GetRestitution(material));

    jolt.JPHX_PhysicsMaterial_Set(material, 0.75, 0.125);
    try std.testing.expectEqual(@as(f32, 0.75), jolt.JPHX_PhysicsMaterial_GetFriction(material));
    try std.testing.expectEqual(@as(f32, 0.125), jolt.JPHX_PhysicsMaterial_GetRestitution(material));
}

test "a material from joltc is not a JPHX material" {
    try std.testing.expectEqual(@as(u32, 0), jolt.JPHX_PhysicsMaterial_GetIndex(null));
    try std.testing.expectEqual(@as(f32, 0), jolt.JPHX_PhysicsMaterial_GetFriction(null));
    try std.testing.expectEqual(@as(f32, 0), jolt.JPHX_PhysicsMaterial_GetRestitution(null));
}
