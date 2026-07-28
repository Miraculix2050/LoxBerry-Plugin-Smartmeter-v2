<?php
// LoxBerry smartmeter Plugin
// git@loxberry.woerstenfeld.de
// 02.03.2017 22:15:45
// ALPHA5
header('Content-Type: text/plain');
header('Content-Disposition: inline; filename="data"');
header('Expires: 0');
header('Cache-Control: must-revalidate');
header('Pragma: public');

$psubdir  	=array_pop(array_filter(explode('/',pathinfo($_SERVER["SCRIPT_FILENAME"],PATHINFO_DIRNAME))));
$directory	="/var/run/shm/$psubdir/";
$dateitypen = array("data");
$configRoot = getenv('LBPCONFIG');
$configCandidates = array_filter(array(
	$configRoot ? "$configRoot/smartmeter.cfg" : null,
	$configRoot ? "$configRoot/$psubdir/smartmeter.cfg" : null,
	"/opt/loxberry/config/plugins/$psubdir/smartmeter.cfg",
));
$pluginConfig = false;
foreach ($configCandidates as $configFile)
{
	if (is_file($configFile))
	{
		$pluginConfig = @parse_ini_file($configFile, true, INI_SCANNER_RAW);
		break;
	}
}

if (is_array($pluginConfig)
	&& isset($pluginConfig['VZLOGGER']['HTTPCACHEENABLED'])
	&& $pluginConfig['VZLOGGER']['HTTPCACHEENABLED'] === '0')
{
	echo "# HTTP cache disabled\n#EOF\n";
	exit(0);
}

if (is_dir($directory)) 
{
	$handle			=opendir($directory) or die("ERROR: $directory not readable");
	while ($file = readdir ($handle)) 
	{
	 if ($file != "." && $file != ".." )
	  {
			$file_data = pathinfo($file);
		  if(in_array($file_data['extension'],$dateitypen))
		  {
			  if (file_exists($directory.$file))
			  {
			    $f = @fopen($directory.$file, "r");
			    if ($f !== false)
			    {
				    readfile($directory.$file);	
						fclose($f);
			    }
			  }
			}
		}
	}
	closedir($handle);
}
else
{
	die("ERROR: $directory not readable");
}
echo "#EOF\n";
exit(0);
