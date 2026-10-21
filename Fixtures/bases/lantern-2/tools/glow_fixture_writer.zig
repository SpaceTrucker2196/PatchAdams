~ synthetic base line 1 ~
~ synthetic base line 2 ~
pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{s}\n", .{"basic"});
}
