Changelog
---------
### 0.3.2 February 15, 2022
- Use `redis.exists?` instead of `redis.exists`.
- Fix deprecated calling commands on `Redis` inside `Redis #pipelined`.

### 0.3.1 April 17, 2016
- Fix `sem.lock(0)` bug (thanks eugenk!).

### 0.3.0 January 24, 2016
- Change API to include non-blocking option for `#lock` (thanks tomclose!).
- Fix unwanted persisting of `available_key` (thanks dany1468!).
- Fix `available_count` returning 0 for nonexisting semaphores (thanks mikeryz!).

### 0.2.4 January 11, 2015
- Fix bug with TIME and redis-namespace (thanks sos4nt!).
- Add expiration option (thanks jcalvert!).
- Update API version logic.

### 0.2.3 September 7, 2014
- Block-based locking return the value of the block (thanks frobcode!).

### 0.2.2 June 16, 2014
- Fixed bug in `all_tokens` (thanks presskey!).
- Fixed bug in error message (thanks Dmitriy!).

### 0.2.1 August 6, 2013
- Remove dependency on Redis 2.6+ using fallback for TIME command (thanks dubdromic!).
- Add ```:use_local_time``` option

### 0.2.0 June 2, 2013
- Use Redis TIME command for lock timeouts (thanks dubdromic!).
- Version increase because of new dependency on Redis 2.6+

### 0.1.7 April 18, 2013
- Fix bug where ```release_stale_locks!``` was not public (thanks scomma!).

### 0.1.6 March 31, 2013
- Add non-ownership of tokens
- Add stale client timeout (thanks timgaleckas!).

### 0.1.5 October 1, 2012
- Add detection of Redis::Namespace definition to avoid potential bug (thanks ruud!).

### 0.1.4 October 1, 2012
- Fixed empty namespaces (thanks ruurd!).

### 0.1.3 July 9, 2012
- Tokens are now identifiable (thanks timgaleckas!).

### 0.1.2 June 1, 2012
- Add redis-namespace support (thanks neovintage!).

### 0.1.1 September 17, 2011
- When an exception is raised during locked period, ensure it unlocks.

### 0.1.0 August 4, 2011
- Initial release.
