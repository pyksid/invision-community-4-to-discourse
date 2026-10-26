# Local test bench

Runs `ipboard4.rb` against a local copy of the IPB database in a Discourse development container, to test
changes before the production import. Paths below are the defaults of the scripts (`~/ipb-dump`); override
them with the variables each script reads.

The IPB copy holds production data (emails, IPs, password hashes, private messages): keep dumps and file
copies outside the repository (`.gitignore` covers `ipb_*.sql`/`ipb_*.txt`) and only run aggregate queries
on it, as `checks.sql` and `upload_list.sh` do.

## Setup

1. **IPB database** (MariaDB, port 3307, root password `local`), then load a dump into the `ipb` database:

   ```
   docker run -d --name ipb-local -e MARIADB_ROOT_PASSWORD=local -p 127.0.0.1:3307:3306 \
       -v ipb-local-data:/var/lib/mysql mariadb:11.8
   docker exec ipb-local mariadb -uroot -plocal -e "CREATE DATABASE ipb CHARACTER SET utf8mb4"
   docker exec -i ipb-local mariadb -uroot -plocal ipb < ipb_dump.sql
   ```

2. **Discourse** checkout and development container, with the IPB uploads mounted read-only at `/ipb-uploads`:

   ```
   git clone --depth 1 https://github.com/discourse/discourse.git ~/ipb-dump/discourse
   mkdir -p ~/ipb-dump/uploads ~/ipb-dump/discourse/data/postgres
   docker run -d --name discourse_dev --hostname discourse \
       -p 127.0.0.1:3000:3000 -p 127.0.0.1:9292:9292 -p 127.0.0.1:9405:9405 -p 127.0.0.1:18025:8025 \
       -v "$HOME/ipb-dump/discourse/data/postgres:/shared/postgres_data:delegated" \
       -v "$HOME/ipb-dump/discourse:/src:delegated" \
       -v "$HOME/ipb-dump/uploads:/ipb-uploads:ro" \
       -e UNICORN_BIND_ALL=true discourse/discourse_dev:release /sbin/boot
   docker exec -u root discourse_dev sh -c 'apt-get update -qq && apt-get install -y -qq default-libmysqlclient-dev'
   docker exec -u discourse:discourse -w /src -e IMPORT=1 discourse_dev bundle install
   docker exec -u discourse:discourse -w /src -e IMPORT=1 discourse_dev bin/rake db:create db:migrate
   ```

   Optional, to test password migration: clone
   [discourse-migratepassword](https://github.com/communiteq/discourse-migratepassword) into
   `~/ipb-dump/discourse/plugins/`, run `bundle install` again and migrate.

3. **Uploads**: only the files the import needs. After a first import, `upload_list.sh` lists the avatars and
   cover photos of the imported members; copy them from the server (its usage comment shows a `tar` over
   `ssh` command for an uploads directory only reachable inside a container).

## Running

```
bench/import.sh              # copies ipboard4.rb, runs the import, waits and prints the summary
bench/import.sh --no-wait    # returns right away; the log is ~/ipb-dump/discourse/tmp/import.log
docker exec -i -u postgres discourse_dev psql discourse_development < bench/checks.sql
```

The import is resumable, so re-running it only processes what is missing or new phases. To start over,
drop and recreate the Discourse database (`bin/rake db:drop db:create db:migrate` with `IMPORT=1`).

## Web server

The full `bin/dev` (Ember build with rolldown) can run out of memory in an 8 GB Docker VM. Build the
front end once, then start Rails only, **with `IMPORT=1`** (otherwise `Gemfile.lock` loses the import gems):

```
docker exec -u discourse:discourse -w /src discourse_dev bin/ember-cli --build
docker exec -d -u discourse:discourse -w /src -e IMPORT=1 -e UNICORN_BIND_ALL=1 -e UNICORN_WORKERS=2 \
    -e LD_PRELOAD=/usr/lib/libjemalloc.so -e RAILS_DISABLE_ACTIVERECORD_LOGS=1 \
    discourse_dev sh -c 'bin/dev --only rails > tmp/server.log 2>&1'
```

Then open http://localhost:3000 and sign in as any user with `/session/<username>/become` (development only).
