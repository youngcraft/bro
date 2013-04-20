
@load base/protocols/ftp
@load base/frameworks/measurement

@load base/utils/time

module FTP;

export {
	redef enum Notice::Type += { 
		## Indicates a host bruteforcing FTP logins by watching for too many
		## rejected usernames or failed passwords.
		Bruteforcing
	};

	## How many rejected usernames or passwords are required before being 
	## considered to be bruteforcing.
	const bruteforce_threshold = 20 &redef;

	## The time period in which the threshold needs to be crossed before
	## being reset.
	const bruteforce_measurement_interval = 15mins &redef;
}


event bro_init()
	{
	local r1: Measurement::Reducer = [$stream="ftp.failed_auth", $apply=set(Measurement::UNIQUE)];
	Measurement::create([$epoch=bruteforce_measurement_interval,
	                     $reducers=set(r1),
	                     $threshold_val(key: Measurement::Key, result: Measurement::Result) =
	                     	{ 
	                     	return result["ftp.failed_auth"]$num;
	                     	},
	                     $threshold=bruteforce_threshold,
	                     $threshold_crossed(key: Measurement::Key, result: Measurement::Result) = 
	                     	{
	                     	local r = result["ftp.failed_auth"];
	                     	local dur = duration_to_mins_secs(r$end-r$begin);
	                     	local plural = r$unique>1 ? "s" : "";
	                     	local message = fmt("%s had %d failed logins on %d FTP server%s in %s", key$host, r$num, r$unique, plural, dur);
	                     	NOTICE([$note=FTP::Bruteforcing, 
	                     	        $src=key$host,
	                     	        $msg=message,
	                     	        $identifier=cat(key$host)]);
	                     	}]);
	}

event ftp_reply(c: connection, code: count, msg: string, cont_resp: bool)
	{
	local cmd = c$ftp$cmdarg$cmd;
	if ( cmd == "USER" || cmd == "PASS" )
		{
		if ( FTP::parse_ftp_reply_code(code)$x == 5 )
			Measurement::add_data("ftp.failed_auth", [$host=c$id$orig_h], [$str=cat(c$id$resp_h)]);
		}
	}