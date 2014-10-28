repo-backup
===========

Many developers use hosting services like GitHub for their source repositories and associated information. But should the hosting service go down, lose data, or become inaccessible, your source may be unavailable! This project allows you to back up your repos to a location you control.

Features
======

* Supports multiple services: [GitHub](http://github.com) and [Gitlab](http://gitlab.com)
* Automatically finds all your repos
* Works with both public and private repos
* Safe for scheduled use, eg: cron

Usage
======

Repo-backup requires Ruby 1.9 or later. It can run on most Unix-likes, including Linux and Mac OS X.

You will need two pieces of information to authenticate with hosting services:
* A SSH private key, for access to repos. You can generate your key pair with `ssh-keygen -t rsa -C your.email@example.com -f key`, which will create a private key `key` and a public key `key.pub`. You must add the public key to your profile on each service. 
* A token for each service's REST APIs. See below for instructions for each service.

You need to create a config.yaml to describe the services you want to backup. Each service should have an arbitrary name, a type (github or gitlab) and an authentication token. Here's a sample file, with fake tokens:
```
- name: github
  type: github
  token: da24c3f95b4fda9e5a6b575357b3ffb9a2e56a7d
- name: service2
  type: gitlab
  token: aekeiQuiaquogh3yieth
```

Now you can perform a backup: `./repo-backup.rb config.yaml key /path/to/backup` . The same command will work to update the existing backup.

To access your backed up repositories just use git, eg: `git clone /path/to/backup/service2/myrepo/repo.git target`

Services
====

GitHub
----
repo-backup will backup:
* code, including all branches
* wiki
* issues and pull requests
* comments on issues and pull-requests

You can add your SSH public key [here](https://github.com/settings/ssh)
You can generate a REST API token [here](https://github.com/settings/applications), under `Personal access tokens`. Your token only needs the `read:org` and `repo` permissions.

Gitlab
----
repo-backup will backup:
* code, including all branches

You can add your SSH public key [here](https://gitlab.com/profile/keys)
You can get a REST API token [here](https://gitlab.com/profile/account), under `Private token`.

Notes
----

Note that most services only allow SSH keys for users, not organizations. If you wish to backup all repos for an organization, you can instead create a [dedicated user](https://developer.github.com/guides/managing-deploy-keys/#machine-users) for backups, and add it to your organization.

Todo
====

* Protect against hung connections, we should just timeout after too long. This might already happen!
* Better permission options
* Easier configuration (eg: OAUTH)
* Backup more info (forks, watchers, ...)
* Add more services
* Add tests

License
=====
(C) 2014 Dave Vasilevsky, Evolving Web

Available under the GNU General Public License version 2 or later
