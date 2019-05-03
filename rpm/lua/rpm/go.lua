-- Copyright © 2017-2019 Nicolas Mailhot <nim@fedoraproject.org>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
--
-- SPDX-License-Identifier: GPL-3.0-or-later

-- This file contains Lua code used in rpm macros to create rpm packages past
-- the srpm stage: anything starting with %prep.
--
-- The sister file gosrpm.lua deals with srpm and buildroot setup and is more
-- restricted.

-- The goenv macro main processing function
-- See the documentation in the macros.go-rpm file for argument description
local function env(suffix, goipath, verbose, usermetadata)
  local  fedora = require "fedora.common"
  local      go = require "fedora.srpm.go"
  local  suffix = suffix
  local goipath = goipath
  local  ismain = (suffix == "") or (suffix == "0")
  if (goipath ~= "") and (suffix == "") then
    local bettersuffix = fedora.getbestsuffix("goipath",goipath)
    if (bettersuffix ~= nil) then
         suffix = bettersuffix
    end
  end
  if (goipath == "") then
    goipath = "%{goipath" .. suffix .. "}"
  end
  suffixes = fedora.getsuffixes("goipath")
  fedora.safeset(             "goworkdir", "%{_builddir}/%{extractdir" .. suffixes[#suffixes] .. "}",                     verbose)
  fedora.safeset(            "gobuilddir", "%{goworkdir}/_build",                                                         verbose)
  if ismain then
    fedora.zalias({"gosourcedir", "gofilelist", "gocid"}, verbose)
  else
    fedora.safeset("gofilelist" .. suffix, go.rpmname("%{goipath" .. suffix .. "}", "%{?gocid" .. suffix .. "}") ..
                                           "-%{gofilelist}",                                                              verbose)
  end
  if rpm.expand("%{goipath" .. suffix .. "}") ~= rpm.expand(goipath) then
    fedora.explicitset("thisgofilelist",   go.rpmname(goipath, "%{?gocid" .. suffix .. "}") .. "-%{gofilelist}",          verbose)
  else
    fedora.explicitset("thisgofilelist",   "%{gofilelist"  .. suffix .. "}",                                              verbose)
  end
  fedora.safeset( "gosourcedir" .. suffix, "%{?extractdir" .. suffix .. ":%{_builddir}/%{extractdir" .. suffix .. "}}" ..
                                          "%{!?extractdir" .. suffix .. ":%{goworkdir}}",                                 verbose)
  if ismain then
    fedora.zalias({"gosourcedir"}, verbose)
  end
  local   ldflags = ""
  local  metadata = { version = { id = "version" }, tag = {}, commit = {}, branch  = {}, }
  table.sort(metadata)
  for m,_ in pairs(metadata) do
    metadata[m]["id"]    = metadata[m]["id"] or "version." .. m
    metadata[m]["value"] = usermetadata[m] or rpm.expand("%{?" .. m .. suffix .. "}")
    if (metadata[m]["value"] ~= '') then
      ldflags = ldflags .. " -X " .. goipath .. "/" ..  metadata[m]["id"] .. "=" .. metadata[m]["value"]
    end
  end
  fedora.setcurrent({"goipath", "gosourcedir", "gofilelist",
                     "version", "tag", "commit", "branch"}, suffix, verbose)
  fedora.explicitset(  "currentgoldflags", ldflags,                 verbose)
end

-- Create a single set of %install tasks for a known kind of Go subpackage
local function singleinstall(kind, suffix, verbose)
  local go = require "fedora.srpm.go"
  if     (kind == "devel")  then
    go.develenv(suffix, verbose)
    for goipath in string.gmatch(rpm.expand("%{currentgoipaths}"), "[^%s]+") do
      env('', goipath, verbose, {})
      local vflag = verbose and " -v" or ""
      print(rpm.expand("%__godevelinstall -i " .. goipath .. vflag .. "\n"))
    end
    print(rpm.expand("%__godevelinstalldoc\n"))
  elseif (kind == "alt") then
    local fedora = require "fedora.common"
    local ismain = (suffix == "") or (suffix == "0")
    if ismain then
      fedora.zalias({"goaltipaths","gocid","goaltcid"},                verbose)
    end
    fedora.safeset("goaltcid" .. suffix, "%{?gocid"  .. suffix .. "}", verbose)
    if ismain then
      fedora.zalias({"goaltcid"},                                      verbose)
    end
    for rpmname, goaltipaths in pairs(go.indexedgoipaths("%{goaltipaths" .. suffix .. "}",
                                                         "%{goaltcid"    .. suffix .. "}")) do
      go.altenv(suffix, rpmname, goaltipaths, verbose)
      gocanonipath = rpm.expand("%{currentgocanonipath}")
      for _, goaltipath in ipairs(goaltipaths) do
        fedora.explicitset("currentgoaltipath", goaltipath)
        print(rpm.expand("%__goaltinstall\n"))
        goaltipath = string.gsub(goaltipath, "/?[^/]+/?$", "")
        while (not string.match(gocanonipath, "^" .. goaltipath)) do
          print(rpm.expand('echo \'%dir "%{gopath}/src/' .. goaltipath .. '"\' >> "%{goworkdir}/%{currentgoaltfilelist}"\n'))
          goaltipath  = string.gsub(goaltipath, "/?[^/]+/?$", "")
        end
      end
    end
  else
    rpm.expand("%{error:Unknown kind of Go subpackage: " .. kind .. "}")
  end
end

-- Create one or all %install tasks for a known kind of go subpackage
local function install(kind, suffix, processall, verbose)
  local fedora = require "fedora.common"
  local go     = require "fedora.srpm.go"
  if (kind == "devel") then
    go.develenvinit()
  end
  if processall then
    for _, suffix in pairs(fedora.getsuffixes(go.pivot[kind])) do
       singleinstall(kind, suffix, verbose)
    end
  else
    singleinstall(kind, suffix, verbose)
  end
end

return {
  env     = env,
  install = install,
}
