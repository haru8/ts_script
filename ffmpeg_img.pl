#!/usr/bin/perl

$infile = $ARGV[0];
$step   = $ARGV[1];
$outdir = $ARGV[2];
$ffmpeg = '/usr/local/bin/ffmpeg';
$thumb_s= "288x162";
$thumb_l= "1280x720";

sub movie_sec {
  my $in_file = $_[0];

  my $time_s = `$ffmpeg -i $in_file 2>&1 | grep 'Duration:' | sed 's/  Duration: //g;s/,.*//;s/\\.[0-9]*//'`;
  my @split = split(/:/, $time_s);
  my $h = $split[0] * 3600;
  my $m = $split[1] * 60;
  my $s = $split[2];
  my $sec = $h + $m + $s;

  return $sec;
}

if ($#ARGV != 2) {
  printf("%s\n", $#ARGV);
  printf("err.\n");
  printf("%s inputfilename step outdir\n", $0);
  exit 1;
}

unless (-e $outdir && -d $outdir) {
  printf("%s not found.\n", $outdir);
  mkdir "$outdir", 0777;
  mkdir "$outdir/l", 0777;
} else {
  printf("%s found.\n", $outdir);
}

$num = 0;
$sec = 0;
$retval1 = 0;

$playsec = &movie_sec($infile);
$nums = $playsec/10;
printf("PLAYSEC=%s  NUMS=%s\n", $playsec, $nums);

while ($retval1 == 0) {
  $num_s = sprintf('%08d', $num);
  $time  = sprintf("%02d:%02d:%02d", int($sec/3600), int($sec/60), $sec%60);
  $cmd1  = "$ffmpeg -y -loglevel quiet -ss $sec -i $infile -vframes 1 -s $thumb_s -f image2 ${outdir}/${num_s}.jpg";
  $cmd2  = "$ffmpeg -y -loglevel quiet -ss $sec -i $infile -vframes 1 -s $thumb_l -f image2 ${outdir}/l/${num_s}.jpg";
  print("$cmd1\n");
  system("$cmd1");
  print("$cmd2\n");
  system("$cmd2");
  $retval1     = $? >> 8;
  $signal_num  = $? & 127;
  $dumped_core = $? & 128;

  #if (! -e "${outdir}/${num_s}.jpg") {
  #  print ("${outdir}/${num_s}.jpg not found.\n");
  #  last;
  #}
  if ($num > $nums) {
    last;
  }
  $num = $num + 1;
  $sec = $sec + $step;

}

