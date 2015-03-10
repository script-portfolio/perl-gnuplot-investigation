#!/usr/bin/perl


use File::Glob ':glob';
use strict;

our $log_filename_mask = './data/catali*';
#our $log_filename_mask = './data/catalina.out';
#our $log_filename_mask = './data/catalina.out.35.gz';

our $ticket_mask = 'com.delta.ScheduledReportServiceImpl ';
our $verbose = 1;

#"filename' -> 'mtime'
our %data = map { $_, { secs => (stat $_ )[9] }  } bsd_glob( $log_filename_mask, GLOB_ERROR );

our $tmpfile = "/tmp/$0.$$";
open TMP, ">$tmpfile" or die "Can not open $tmpfile: $!";

our %analyse;
my ($pipe_cmd, $moment1, $moment2, $diff_sec, $tag, $year );
my ($first_rank, $last_rank);
my ($tmp, $month);

foreach my $log_file ( sort { $data{$a}->{secs} <=> $data{$b}->{secs} } keys %data ) {
  $data{$log_file}->{first} = `grep $ticket_mask $log_file | head -1`;
  $data{$log_file}->{last} =  `grep $ticket_mask $log_file | tail -1`;
  $data{$log_file}->{mtime} = `stat -c '%y' $log_file | cut -d '.' -f 1 `; 
  $year                     = `stat -c '%y' $log_file | cut -d '-' -f 1 `; chop $year; 

  $pipe_cmd = "cat $log_file | grep $ticket_mask |  ";
  $pipe_cmd = "zcat $log_file | grep $ticket_mask |  " if $log_file =~ /gz$/;
  open LF, $pipe_cmd;
  while (<LF>) {
    chop;

    if( m/^(.+?) ${ticket_mask}Processing alerts reports for (.+?)$/ ) {
      $moment1 = getStrTimeStamp( $year, $_ );
			$first_rank = $moment1 if not defined $first_rank;
      if( $tag ) {
        # Error 1
        #printf "%-20s %24s %s\n", uc $log_file, $tag, "$moment1 -100" if $verbose;
      }
      $tag  = $2;
    } 

    if( m/^(.+?) ${ticket_mask}Completed processing alerts reports for (.+)$/ ) {
      $moment2 = getStrTimeStamp( $year, $_ );
      if( not defined $tag ) {
        # Error 2
        #printf  "%-20s %24s %s\n",  uc $log_file, $2, "$moment2 -200" if $verbose;
        undef $tag;
        next;
      } elsif( ! $tag && $tag ne $2 ) {
        printf STDERR "Untested Error. Breaking.\n";
        exit;
      }
      $diff_sec = getTimeStampDiff( $moment2, $moment1 );
      if( $diff_sec ) {
        printf "%-20s %24s %s\n", $log_file, $tag, "$moment1 $diff_sec" if $verbose;
        print TMP "$moment1 $diff_sec\n";
        $analyse{$tag}->{cnt}++;
        $analyse{$tag}->{total} += $diff_sec;
      } else {
        $analyse{$tag}->{cnt0}++;
      }
      undef $tag;
    }
  }
  close LF;
}
$last_rank = $moment1;
close TMP;


$first_rank=sec2date( date2sec( $first_rank) -60*60*24*10);
$last_rank =sec2date( date2sec( $last_rank ) +60*60*24*10);



my $gnu_script=<<EOS;
set title "Queries http://\${PORTAL_URL}:8083/portal-server-reporting/scheduledReports\\nfor prod-c0-wb1"
set ylabel "Secs"
#set timefmt "%d/%m/%y\t%H%M"
set terminal png  
set size 1.5,1.5
set grid
set output "graph.png"
set xdata time
set xlabel "Month/Year"
set format x "%b/%y"
set timefmt "%Y-%m-%d %H:%M:%S"
set function style line
plot ["$first_rank":"$last_rank"] "$tmpfile" using 1:3 with impulse
EOS



my $gnu_cmd="/tmp/$0.gnu_cmd_file.$$";
open GNU_CMD_FILE,">$gnu_cmd";
print GNU_CMD_FILE $gnu_script;
close GNU_CMD_FILE;


print `gnuplot $gnu_cmd`;

print "Successfuly handled clients: ", scalar keys %analyse, 

print "\n";
print $gnu_script;
print "\n";

foreach my $item ( sort { $analyse{$b}->{total} <=> $analyse{$a}->{total} } keys %analyse ) {
  next if ! $analyse{$item}->{cnt}  and ! $analyse{$item}->{total};
  printf "%24s %d %d %d\n", $item, $analyse{$item}->{cnt0}, $analyse{$item}->{cnt}, $analyse{$item}->{total};
}


#unlink  $tmpfile;

####################
sub date2sec() {
  my $date=shift;
  $date = `date -d '$date' +'%s'`; chop $date;
	return $date;
}

sub sec2date() {
	my $sec=shift;
	# debug cmd:
    # perl -e ' print scalar localtime 1209333601, "\n"' | xargs -i date -d '{}' +'%F %T'
	my $str = scalar localtime $sec;
    my $date=`date -d	'$str' +'%F %T'`; chop $date;
	return $date;
}

sub getTimeStampDiff() {
  my $d1 = shift;
  my $d2 = shift;
  $d1 = `date -d '$d1' +'%s'`; chop $d1;
  $d2 = `date -d '$d2' +'%s'`; chop $d2;
  return $d1 - $d2;
}

sub getStrTimeStamp() {
  my $year = shift;
  my $line = shift;
	my ($check,$month);
  $_ = $line;
  my ($sec, $const);
  if ( m/^(.+?)\s(.+?)\s.*/ )  {
    $const = $_ = "$1 $2";
    if( m/(\d{2})-\d{2} \d{2}:\d{2}:\d{2}/ ) {
	    #$month =~ s/\d{4}-(\d{2})\D.*/$1/;
			if ( $year == 2009 and $1 == 12 ) {
	    $year -= 1; 
			}
		  #$check = `date +'%F %T'`; chop $check;
      #--$year if not ( $year == 2009 and $1 == "01" );
      return "$year-$const";
    }
  }
  print $year, ' * ', $line;
  print 'Data Error';
  exit;
}
