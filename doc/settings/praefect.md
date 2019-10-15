# Praefect

NOTE: **Note** Praefect support is EXPERIMENTAL at this time. We do not
recommend using it in production yet.

Praefect is a manager aiming to maintain replicas for each repository. Praefect
is in active development, and while the goal is to achieve an highly available
storage cluster, this is not the case yet. Given it is the goal however, it's
advised to run Praefect on a different node than the Gitaly nodes.

```ruby
praefect['enable'] = true
```

## Praefect settings

How to setup Praefect, is documented in [the administration documentation][admin-docs].

### Praefect storage nodes

Praefect needs 1 or more Gitaly servers to store the Git data on. These
Gitaly servers are considered praefects `storage_nodes`
(`praefect['storage_nodes']`). These storage nodes should be private to
Praefect, meaning they should not be listed in `git_data_dirs` in your
`gitlab.rb`.

[admin-docs]: https://docs.gitlab.com/ee/administration/gitaly/praefect.html#enable-the-daemon