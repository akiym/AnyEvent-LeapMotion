package AnyEvent::LeapMotion;
use 5.008005;
use strict;
use warnings;
use AnyEvent::Handle;
use AnyEvent::Socket ();
use JSON ();
use Protocol::WebSocket;
use Protocol::WebSocket::Frame;
use Protocol::WebSocket::Handshake::Client;

our $VERSION = "0.01";

sub new {
    my ($class, %args) = @_;
    return bless {
        host           => '127.0.0.1',
        port           => 6437,
        enable_gesture => 0,
        %args,
        frame => Protocol::WebSocket::Frame->new(),
    }, $class;
}

sub run {
    my ($self, $code) = @_;
    AnyEvent::Socket::tcp_connect $self->{host}, $self->{port}, sub {
        my ($fh, $host, $port) = @_ or die "connection failed: $!";
        $self->{handle} = AnyEvent::Handle->new(
            fh => $fh,
            on_eof => sub {
                $_[0]->destroy;
            },
            on_error => sub {
                $self->call(on_error => $_[1]);
                $_[0]->destroy;
            },
        );
        my $hs = Protocol::WebSocket::Handshake::Client->new(
            url => "ws://$self->{host}:$self->{port}",
        );
        $self->{handle}->push_write($hs->to_string);
        $self->{handle}->on_read(sub {
            $self->{handle}->push_read(sub {
                $hs->parse(delete $_[0]->{rbuf});
                unless ($hs->is_done) {
                    $self->call(on_error => 'Handshake failed');
                }
            });
            if ($self->{enable_gesture}) {
                $self->send({enableGestures => \1}); # true
            }
            $self->{handle}->on_read(sub {
                $_[0]->push_read(sub {
                    $self->{frame}->append(delete $_[0]->{rbuf});
                    if (my $message = $self->{frame}->next_bytes) {
                        my $data = JSON::decode_json($message);
                        if (exists $data->{id} && exists $data->{timestamp}) {
                            $self->call(on_frame => $data);
                        }
                    }
                });
            });
        });
    };
}

sub send {
    my ($self, $data) = @_;
    my $message = JSON::encode_json($data);
    my $frame = Protocol::WebSocket::Frame->new($message);
    $self->{handle}->push_write($frame->to_bytes);
}

sub call {
    my ($self, $name, @args) = @_;
    if ($self->{$name}) {
        $self->{$name}->(@args);
    }
}

1;
__END__

=encoding utf-8

=head1 NAME

AnyEvent::LeapMotion - Perl interface to the Leap Motion Controller (via WebSocket)

=head1 SYNOPSIS

    use AnyEvent;
    use AnyEvent::LeapMotion;

    my $leap = AnyEvent::LeapMotion->new(
        enable_gesture => 1,
        on_frame => sub {
            my $frame = shift;

            ...
        },
    );
    $leap->run;

    AE::cv->recv;

=head1 DESCRIPTION

AnyEvent::LeapMotion is ...

=head1 SEE ALSO

L<Device::Leap>

=head1 LICENSE

Copyright (C) Takumi Akiyama.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Takumi Akiyama E<lt>t.akiym@gmail.comE<gt>

=cut

