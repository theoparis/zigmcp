const std = @import("std");
const mem = std.mem;
const math = std.math;
const Allocator = mem.Allocator;
const assert = std.debug.assert;
const testing = std.testing;

const zuid = @import("zuid");

const serde = @import("serde.zig");
const PrefixedArray = serde.PrefixedArray;

const VarI32 = @import("varint.zig").VarInt(i32);

pub fn BitSet(comptime capacity: comptime_int) type {
    return struct {
        pub const E = error{EndOfStream};
        pub const UT = @This();
        pub const MaxLongs = longCount(capacity);
        pub const Length = math.IntFittingRange(0, MaxLongs);
        pub const LengthSpec = serde.RestrictInt(
            serde.Casted(VarI32, Length),
            .{ .max = MaxLongs },
        );

        buffer: [MaxLongs]u64 = .{0} ** MaxLongs,
        len: Length = 0,

        pub fn write(writer: anytype, in: UT, ctx: anytype) !void {
            try LengthSpec.write(writer, in.len, ctx);
            for (in.buffer[0..in.len]) |d| try writer.writeInt(u64, d, .big);
        }
        pub fn read(reader: anytype, out: *UT, ctx: anytype) !void {
            try LengthSpec.read(reader, &out.len, ctx);
            for (out.buffer[0..out.len]) |*d| d.* = try reader.readInt(u64, .big);
        }
        pub fn size(self: UT, ctx: anytype) usize {
            return LengthSpec.size(self.len, ctx) + (@sizeOf(u64) * @as(usize, self.len));
        }
        pub fn deinit(self: *UT, _: anytype) void {
            self.* = undefined;
        }

        pub inline fn longCount(bit_count: usize) usize {
            return (bit_count + 63) >> 6;
        }

        pub fn initEmpty(bit_count: usize) UT {
            return .{
                .len = @intCast(longCount(bit_count)),
            };
        }
        pub fn get(self: UT, i: usize) bool {
            if (i < @as(usize, self.len) << 6) {
                return (self.buffer[i >> 6] & (@as(u64, 1) << @as(u6, @truncate(i)))) != 0;
            } else {
                return false;
            }
        }
        pub fn set(self: *UT, i: usize) void {
            assert(i < @as(usize, self.len) << 6);
            self.buffer[i >> 6] |= @as(u64, 1) << @as(u6, @truncate(i));
        }
        pub fn unset(self: *UT, i: usize) void {
            assert(i < @as(usize, self.len) << 6);
            self.buffer[i >> 6] &= ~(@as(u64, 1) << @as(u6, @truncate(i)));
        }
    };
}

/// String serialization type
pub fn PString(comptime max_len_opt: ?comptime_int) type {
    return serde.Pass(
        serde.RestrictInt(
            serde.Casted(VarI32, usize),
            // actual max len is supposed to be number of utf16 code units, which, for
            //     every 2 code units, we say that is a codepoint, which has a max of 4.
            //     therefore i will say that we will treat max len as max number of
            //     bytes divided by 2. (hopefully this works fine? TODO: look at this)
            // TODO: actually measure code units?
            .{ .max = if (max_len_opt) |l| l * 2 else null },
        ),
        serde.DynamicArray(u8),
    );
}

pub const Uuid = struct {
    pub const UT = [16]u8;
    pub const E = error{EndOfStream};
    pub fn write(writer: anytype, in: UT, _: anytype) !void {
        try writer.writeAll(&in);
    }
    pub fn read(reader: anytype, out: *UT, _: anytype) !void {
        try reader.readNoEof(out);
    }
    pub fn deinit(self: *UT, _: anytype) void {
        self.* = undefined;
    }
    pub fn size(self: UT, _: anytype) usize {
        return self.len;
    }
    // stolen from https://github.com/regenerativep/zig-mc-server/blob/d82dc727311fd10d2e404ebb4715336637dcca97/src/mcproto.zig#L137
    // referenced https://github.com/AdoptOpenJDK/openjdk-jdk8u/blob/9a91972c76ddda5c1ce28b50ca38cbd8a30b7a72/jdk/src/share/classes/java/util/UUID.java#L153-L175
    pub fn fromUsername(username: []const u8) UT {
        assert(username.len <= 16);
        const ofp = "OfflinePlayer:";
        var buf = ofp.* ++ ([_]u8{undefined} ** 16);
        @memcpy(buf[ofp.len..][0..username.len], username);
        var uuid: UT = undefined;
        std.crypto.hash.Md5.hash(buf[0 .. ofp.len + username.len], &uuid.bytes, .{});
        uuid.setVersion(.name_based_md5);
        uuid.setVariant(.rfc4122);
        return uuid;
    }
};

pub const Angle = struct {
    pub usingnamespace serde.Num(u8, .big);
    pub fn fromF32(val: f32) u8 {
        return @intCast(@mod(@as(isize, @intFromFloat((val / 360.0) * 256.0)), 256));
    }
};

pub fn V3(comptime T: type) type {
    return struct { x: T, y: T, z: T };
}

pub const Position = packed struct(u64) {
    y: i12,
    z: i26,
    x: i26,
};
