// Silent refresh of the operator's existing Cloudflare CLI session. The caller
// captures stdout in memory and never persists this short-lived OAuth token.
try {
  const { t: createAuth } = await import(process.argv[2]);
  const noop = () => {};
  const auth = createAuth({logger:{debug:noop,info:noop,log:noop,warn:noop,error:noop},userAgent:'onestack-security-readonly/1.0'});
  const status = await auth.loginOrRefreshIfRequired({}, {browser:false,device:false});
  const credentials = auth.readAuthCredentials();
  if (!status.loggedIn || !credentials?.oauth_token || Date.parse(credentials.expiration_time) <= Date.now()+30_000) throw Error('Existing session unavailable');
  process.stdout.write(await auth.getOAuthTokenFromLocalState());
} catch {
  process.stderr.write('Existing Cloudflare CLI session unavailable\n');
  process.exitCode=1;
}
