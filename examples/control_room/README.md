# ControlRoom

Example of how to use `IEC104.ControllingConnection`. This application
connects to a substation, and prints all received telegrams.

You can run the application with `mix run --no-halt`. ControlRoom will assume
that a substation is listening for connections on localhost, port 2404. You
can set the environment variables `substation_host` (hostname or IP address)
and `substation_port` (integer) to connect somewhere else. E.g.
`substation_host=substation.example.org substation_port=24040 mix run
--no-halt`.
