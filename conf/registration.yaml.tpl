id: rocketchat_%%unique_id%%
hs_token: %%homeserver_token%%
as_token: %%appservice_token%%
url: http://%%rocketchat_container%%:3300
sender_localpart: rocket.cat
de.sorunome.msc2409.push_ephemeral: %%share_ephemeral_updates%%
namespaces:
  users:
    - exclusive: false
      regex: .*
  rooms:
    - exclusive: false
      regex: .*
  aliases:
    - exclusive: false
      regex: .*
rocketchat:
  homeserver_url: http://%%matrix_container%%:8008
  homeserver_domain: %%matrix_domain%%
