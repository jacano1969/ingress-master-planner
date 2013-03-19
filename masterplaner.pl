#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: masterplaner.pl
#
#        USAGE: ./masterplaner.pl sourcefile.csv
#
#  DESCRIPTION: Produce a KML file showing the Maximum links for a given area.
#               -Show links that can be created given current keys.
#               -Give preference to a specific player.
#               -textual output of links
#               -report of consumed keys
#
# REQUIREMENTS: Math::Geometry::Delaunay
#       AUTHOR: Adam Fairbrother (Hegz), adam.fairbrother@gmail.com
#      VERSION: 1.0
#      CREATED: 13-03-11 01:08:57 PM
#===============================================================================

use strict;
use warnings;
use Math::Geometry::Delaunay qw(TRI_CCDT);
use Scalar::Util qw(looks_like_number);

# Players in descending order of preference
my @player_prefs = ( '' );

my @file = <>;

#Player hash format:playerkey,Colour 
my %players;

# Read names and colours from the datafile and store in the %players hash
my $players = shift(@file);
my $colours = shift(@file);
chomp $players;
chomp $colours;
$colours =~ s/#//g;

my @names = split(/,/,$players);
my @colours = split(/,/,$colours);
for (my $count = 5; $count >= 1; $count--) {
	shift @names;
	shift @colours;
}
for (my $count = scalar(@names) - 1 ; $count >= 0; $count--) {
	$players{$names[$count]} = $colours[$count];
}

#portal hash.  Format $portals{Portal_name}->{nick=>Nickname, x_cord=>x, y_cord=>y, {player}=>{keys}}
my %portals;
#Read in Datafile
for (@file) {
	chomp;
	s/"//g;
	my ($x,$y,$name,$nick,$tkeys,$nkeys,@keys) = split(/,/);
	$portals{$name} = {nick => $nick, x_cord => $x, y_cord => $y};
	for (my $count = scalar(@names)-1; $count >= 0; $count--) {
		$portals{$name}->{$names[$count]} = $keys[$count];
	}
}

# Points array for Triangifiaction
my @points;
for my $portal (keys %portals) {
	push @points, [ $portals{$portal}->{x_cord}, $portals{$portal}->{y_cord} ];
}

#Triangleificate
my $tri = new Math::Geometry::Delaunay();
$tri->addPoints(\@points);
$tri->doEdges(1);
$tri->doVoronoi(1);
$tri->triangulate();

my $links = $tri->edges();

my $stats = "Total Number of fields: " . scalar @{$tri->vnodes} . "\n" . "Total Number of Links: " . scalar @{$tri->edges} . "\n";

# Number of Links per player
my %player_links;
for (@names) {
	$player_links{$_} = 0;
}

# List of linking instructions $order{source} -> {target, player}
my %orders;

for my $player (@player_prefs) {
	my %portalkeys = ();
	for my $portal (keys %portals) {
		if (defined $portals{$portal}->{$player}) {
			$portalkeys{$portal} = $portals{$portal}->{$player};
		}
		else {
			$portalkeys{$portal} = 0;
		}
	}
	for my $key ( sort { $portalkeys{$b} <=> $portalkeys{$a} } keys %portalkeys ){
		LINK: for my $link ( @{$links} ) {
			next LINK unless ( defined $link );
			if ( ${${$link}[0]}[0] == $portals{$key}->{'x_cord'} && ${${$link}[0]}[1] == $portals{$key}->{'y_cord'} && $portalkeys{$key} gt 0) {
				if (keylink(${$link}[1], $key, \%portalkeys, $player)){
					$link = undef;
				next LINK;
				}
			}
			elsif ( ${${$link}[1]}[0] == $portals{$key}->{'x_cord'} && ${${$link}[1]}[1] == $portals{$key}->{'y_cord'} && $portalkeys{$key} gt 0) {
				if (keylink(${$link}[0], $key, \%portalkeys, $player)){
					$link = undef;
				next LINK;
				}
			}
		}
	}
}
my %portalkeys;

for my $portal (keys %portals){
	my $keys = 0;
	for my $player (keys %players) {
		if (looks_like_number($portals{$portal}->{$player})) {
			$keys += $portals{$portal}->{$player};
		}
	}
	$portalkeys{$portal} = $keys;
}
for my $key ( sort { $portalkeys{$b} <=> $portalkeys{$a} } keys %portalkeys ){
	LINK: for my $link ( @{$links} ) {
		next LINK unless ( defined $link );
		if ( ${${$link}[0]}[0] == $portals{$key}->{'x_cord'} && ${${$link}[0]}[1] == $portals{$key}->{'y_cord'} && $portalkeys{$key} gt 0) {
			if (keylink(${$link}[1], $key, \%portalkeys)){
				$link = undef;
				next LINK;
			}
		}
		elsif ( ${${$link}[1]}[0] == $portals{$key}->{'x_cord'} && ${${$link}[1]}[1] == $portals{$key}->{'y_cord'} && $portalkeys{$key} gt 0) {
			if (keylink(${$link}[0], $key, \%portalkeys)){
				$link = undef;
				next LINK;
			}
		}
	}
}



sub keylink {
# Add a link from a source portal($key) to the target, along with a player that has the key.
	my	( $link, $key, $portalkeys, $player )	= @_;
	unless (defined $player) {
		# Give this link to the player with the least links, unless we're told what player to use.
		CHOOSER: for my $p ( sort { $player_links{$a} <=> $player_links{$b} } keys %player_links ) {
			if (defined $portals{$key}->{$p} &&  $portals{$key}->{$p} gt 0) {
				$player = $p;
				last CHOOSER;
			}
		}
	}

	FINDER: for (keys %portals) {
		# Find the Target portal, and add it all to the hash
		if ($portals{$_}->{'x_cord'} == ${$link}[0] && $portals{$_}->{'y_cord'} == ${$link}[1] && $key ne $_) {
			push @{$orders{$_}}, {target => $key, player => $player};
			$portalkeys->{$key}--;
			$player_links{$player} += 1;
			$portals{$key}->{$player} -= 1;
			return 1;
		}
	}
	return 0;
} ## --- end sub keylink


my $missed_links;
#Load on any remainders
LINK: for my $link ( @{$links} ) {
	next unless ( defined $link );
	$missed_links++;
	for my $key (keys %portals) {
		if (${${$link}[0]}[0] == $portals{$key}->{'x_cord'} && ${${$link}[0]}[1] == $portals{$key}->{'y_cord'}) {
			for (keys %portals) {
				if ($portals{$_}->{'x_cord'} == ${${$link}[1]}[0] && $portals{$_}->{'y_cord'} == ${${$link}[1]}[1]) {
					push @{$orders{$_}}, {target => $key};
					$link = undef;
					next LINK;
				}
			}
		}
	}
}


#Print output
# Begin Document
print "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
print "<kml xmlns=\"http://earth.google.com/kml/2.2\">\n";
print "<Document>\n";
print "  <name>Kamloops Portals - Max Links</name>\n";
print "  <description><![CDATA[Autogenerated Max links.\n";
print "";
print "$stats";
print "currently $missed_links links short of a full wipe\n\n";
for (keys %player_links) {
	print "$_ $player_links{$_}\n";
}
print "]]></description>\n";

# Set default link colour for no Keys
print "  <Style id=\"linknokey\">\n";
print "    <LineStyle>\n";
print "      <color>FF000000</color>\n";
print "      <width>2</width>\n";
print "    </LineStyle>\n";
print "  </Style>\n";

# Set link colours for players with matching keys
for (@names){
	print "  <Style id=\"link$_\">\n";
	print "    <LineStyle>\n";
	print "      <color>FF" .  scalar reverse($players{$_}) . "</color>\n";
	print "      <width>5</width>\n";
	print "    </LineStyle>\n";
	print "  </Style>\n";
}

#Set Default Portal Style
print "   <Style id=\"Portal\">\n";
print "     <LabelStyle>\n";
print "       <color>FFAA0000</color>\n";
print "     </LabelStyle>\n";
print "   </Style>\n";

# Load all portal markers.
for (keys %portals) {
	print "   <Placemark>\n";
	print "     <name>$_</name>\n";
	print "     <styleUrl>#Portal</styleUrl>\n";
	print "     <Point>\n";
	print "       <coordinates>" . $portals{$_}->{'x_cord'} . "," . $portals{$_}->{'y_cord'} .",0</coordinates>\n";
	print "     </Point>\n";
	print "   </Placemark>\n";
}

for my $source (keys %orders){
	for (@{$orders{$source}}) {
	print "  <Placemark>\n";
	print "    <Snippet></Snippet>\n";
	print "    <description><![CDATA[]]></description>\n";

	if (defined $_->{'player'}){
		print "    <styleUrl>#link" . $_->{'player'} . "</styleUrl>\n";
		print "    <name>" . $_->{'player'} . " key link to " . $_->{'target'} . "</name>\n";
	}
	else {
		print "    <styleUrl>#linknokey</styleUrl>\n";
		print "    <name>Link</name>\n";
	}
	print "    <LineString>\n";
	print "      <tessellate>1</tessellate>\n";
	print "      <coordinates>\n";
	print "        " . $portals{$source}->{x_cord} . "," . $portals{$source}->{y_cord} . ",0\n";
	print "        " . $portals{$_->{target}}->{x_cord} . "," . $portals{$_->{target}}->{y_cord} . ",0\n";
	print "      </coordinates>\n";
	print "    </LineString>\n";
	print "  </Placemark>\n";
	}
}

# Close Document
print "</Document>\n";
print "</kml>\n";

open my $marching_orders, '>', 'orders.txt';
for (sort {$orders{$a} cmp $orders{$b}} keys %orders) {
	print $marching_orders "From Portal $_";
	print $marching_orders " (" . $portals{$_}->{nick} . ")" if $portals{$_}->{nick} ne "";
	print $marching_orders "\n";
	for (@{$orders{$_}}) {
		next unless defined $_->{'player'};
		print $marching_orders "- ". $_->{'player'} . " link to " . $_->{'target'} ;
		print $marching_orders " (" . $portals{$_->{target}}->{nick} . ")" if $portals{$_->{target}}->{nick} ne "";
		print $marching_orders "\n";
	}
	print $marching_orders "\n";
	}
	print $marching_orders "Keys Consumed\n";
	for my $player (keys %players) {
		my %keys;
		for ( keys %orders ) {
			for (@{$orders{$_}}){
				if (defined $_->{'player'} && $_->{'player'} eq $player) {
					$keys{$_->{target}}++;
				}
			}
		}
		print $marching_orders "$player keys\n";
		for (sort { $keys{$b} <=> $keys{$a}} keys %keys) {
			print $marching_orders "$keys{$_} \t $_";
			print $marching_orders " (" . $portals{$_->{target}}->{nick} . ")" if $portals{$_->{target}}->{nick} ne "";
			print $marching_orders "\n";
		}
		print $marching_orders "\n";

}

exit 0;

