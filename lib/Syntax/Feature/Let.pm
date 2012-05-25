use strictures 1;

# ABSTRACT: Let block scoping keyword

package Syntax::Feature::Let;

use Devel::CallParser   qw( );
use XSLoader            qw( );
use Sub::Install        qw( install_sub );

use namespace::clean;

our $VERSION = 0.001000;

XSLoader::load('Syntax::Feature::Let', $VERSION);

sub install {
    my ($class, %arg) = @_;
    install_sub {
        into    => $arg{into},
        as      => 'let',
        code    => \&let,
    };
}

sub import {
    my ($class) = @_;
    $class->install(into => scalar caller);
}

1;

__END__

=head1 SYNOPSIS

    use syntax qw( let );

    my $value = let ($x = 23) { $x * 2 };

=head1 DESCRIPTION

This syntax extension introduces a C<let> keyword similar to those found
in Scheme. It is basically a short form of declaring lexicals and having
a block in which those lexicals will be available.

=head2 Syntax

    let (<variable> = <expression>) ... { <body> }

The syntax is triggered with the C<let> keyword, followed by a sequence
(can be none at all, or many) of variable declarations, followed by a
block in which the declared variables will be available.

Currently, only single variables can be initialized inside a variable
declaration:

    let ($x = 23) { $x }
    let (@y = (3..7)) { @y }
    let (%z = (x => 42)) { $z{x} }

=head2 Expression Details

The whole C<let> keyword is an expression, not a statement. This means you
must terminate the statement yourself. It also means the C<let>
expressions can be used inside any other expression:

    my $x = let ($y = 23) { $y } + let ($z = 42) { $z };

The context will also be properly propagated to the block.

=head2 Sequential Access

The lexicals that are declared can be sequentially accessed. This means
that every variable can access those before it:

    let ($x = 23) ($y = $x * 2) { $y }

=head2 Transformation

Internally, the C<let> expression will be turned into a C<do> expression.
This is done at an Op tree level and should result in rather fast code.

    let ($x = 23) { say $x }

will be transformed into (more or less):

    do { my $x = 23; say $x }

=head1 CONTRIBUTORS

=over

=item * Florian Ragwitz (FLORA) - Did all the smart stuff in this module.

=item * Robert Sedlacek - Wrapped it up, put some docs on it.

=back

=head1 SEE ALSO

L<syntax>

=cut
