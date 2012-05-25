use strictures 1;
use Test::More;
use Test::Fatal;

use syntax qw( let );

ok let { 1 }, 'simple';
is let { 23 }, 23, 'returned value';

is let ($x = 23) { $x }, 23, 'simple scalar variable';
is_deeply let (@x = (3..5)) { [@x] }, [3..5], 'simple array variable';
is_deeply let (%x = (3..6)) { +{%x} }, {3..6}, 'simple hash variable';

#is_deeply let (($x, $y) = (4, 5)) { $x + $y }, 9, 'multiple values';

is_deeply [23, let ($x = 42) { $x }], [23, 42], 'constant and let';
is_deeply [let ($x = 42) { $x }, 23], [42, 23], 'let and constant';

is_deeply [let ($x = 23) { $x }, let ($y = 42) { $y }], [23, 42],
    'multiple expressions with different variable names in one line';

is_deeply [let ($x = 23) { $x }, let ($x = 42) { $x }], [23, 42],
    'multiple expressions with same variable name in one line';

is_deeply [let ($x = 3) ($y = 7) { $x .. $y }], [3..7], 'list context';

is_deeply scalar(let (@x = (3..6)) { @x }), 4, 'array in scalar context';

is exception {
    is((let ($x = 4) { sub { $x * shift } })->(3), 12, 'closure');
}, undef, 'can use closure';

is scalar let ($x = 5) ($y = 8) {
    let ($u = 11) ($v = 16) {
        let (@x = ($x..$y)) {
            let (@u = ($u..$v)) {
                @x + @u;
            }
        }
    }
}, 10, 'nested levels';

is exception {
    is let ($x = 3) ($y = 4) ($z = 5) {
        let ($v = $x * 2) { $v }
        +
        let ($v = $y * 2) { $v }
        +
        let ($v = $z * 2) { $v }
    }, 24, 'multiple in same expression and on same level';
}, undef, 'can use in math expressions';

is exception {
    my $x = 23;
    is let ($x = 42) ($y = $x * 2) { $y }, 84, 'sequential access';
}, undef, 'can access previous variable';

is exception {
    my $add = sub {
        let ($x = shift) ($y = shift) {
            return $x . $y if shift;
            return $x + $y;
        };
    };
    is $add->(3, 5), 8, 'fixed return';
    is $add->(3, 5, 1), 35, 'conditional return';
}, undef, 'can return from function';

my $wa_check = sub {
    return let ($x = 23) {
        wantarray ? 'y' : 'n';
    };
};

is_deeply [$wa_check->()], ['y'], 'wantarray true';
is scalar($wa_check->()), 'n', 'wantarray false';

done_testing;
