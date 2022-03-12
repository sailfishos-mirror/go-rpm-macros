-- Copyright (c) 2017-2019 Nicolas Mailhot <nim@fedoraproject.org>
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

-- This file contains Lua code used in rpm macros needed to create and process
-- source rpm (srpm) Go (golang) packages.
--
-- The resulting code must not use any package except redhat-rpm-macros

-- Sanitize a Go import path that can then serve as rpm package name
-- Mandatory parameter: a Go import path
local function rpmname(goipath, compatid)
  -- lowercase and end with '/'
  local   goname = string.lower(rpm.expand(goipath) .. "/")
  -- remove eventual protocol prefix
  goname         = string.gsub(goname, "^http(s?)://",         "")
  -- remove eventual .git suffix
  goname         = string.gsub(goname, "%.git/+",              "")
  -- remove eventual git. prefix
  goname         = string.gsub(goname, "^git%.",               "")
  -- remove FQDN root (.com, .org, etc)
  -- will also remove vanity FQDNs such as "tools"
  goname         = string.gsub(goname, "^([^/]+)%.([^%./]+)/", "%1/")
  -- add golang prefix
  goname         = "golang-" .. goname
  -- compat naming additions
  local compatid = string.lower(rpm.expand(compatid))
  if  (compatid ~= nil) and (compatid ~= "") then
    goname       = "compat-" .. goname .. "-" .. compatid
 end
  -- special-case x.y.z number-strings as that’s an exception in our naming
  -- guidelines
  repeat
    goname, i    = string.gsub(goname, "(%d)%.(%d)",           "%1:%2")
  until i == 0
  -- replace various separators rpm does not like with -
  goname         = string.gsub(goname, "[%._/%-~]+",            "-")
  -- because of the Azure sdk
  goname         = string.gsub(goname, "%-for%-go%-",          "-")
  -- Tokenize along - separators and remove duplicates to avoid
  -- golang-foo-foo-bar-foo names
  local result = ""
  local tokens = {}
  tokens["go"]     = true
  for token in string.gmatch(goname, "[^%-]+") do
     if not tokens[token] then
        result = result .. "-" .. token
        tokens[token] = true
     end
  end
  -- reassemble the string, restore x.y.z runs, convert the vx.y.z
  -- Go convention to x.y.z as prefered in rpm naming
  result = string.gsub(result, "^-", "")
  result = string.gsub(result, ":", ".")
  -- some projects have a name that end up in a number, and *also* add release
  -- numbers on top of it, keep a - prefix before version strings
  result = string.gsub(result, "%-v([%.%d]+)$", "-%1")
  result = string.gsub(result, "%-v([%.%d]+%-)", "-%1")
  return(result)
end

-- The gometa macro main processing function
-- See the documentation in the macros.go-srpm file for argument description
local function meta(suffix, verbose, informative, silent)
  local  fedora = require "fedora.common"
  local   forge = require "fedora.srpm.forge"
  local zsuffix = ""
  if (suffix ~= "") then
        zsuffix = " -z " .. suffix
  end
  local ismain = (suffix == "") or (suffix == "0")
  if ismain then
    fedora.zalias({"forgeurl", "goipath", "gocid", "goname", "gourl", "gosource"}, verbose)
  end
  local spec = {}
  for _, v in ipairs({'goipath', 'forgeurl'}) do
    spec[v] = rpm.expand("%{?" .. v .. suffix .. "}")
  end
  -- All the Go packaging automation relies on goipath being set
  if (spec["goipath"] == "") then
    rpm.expand("%{error:Please set the Go import path in the %%{goipath" .. suffix .. "} variable before calling %%gometa" .. zsuffix .. "!}")
  end
  local cleangoipath = string.gsub(spec["goipath"], "^http(s?)://", "")
  cleangoipath       = string.gsub(cleangoipath,    "/+$",          "")
  if (cleangoipath ~= spec["goipath"]) then
    fedora.explicitset(goipath .. suffix, cleangoipath)
  end
  if (spec["forgeurl"] == "") then
    fedora.safeset("forgeurl"    .. suffix, "https://%{goipath" .. suffix .. "}",verbose)
  end
  forge.meta(suffix, verbose, informative, silent)
  fedora.safeset("gourl"    .. suffix, "%{forgeurl"        .. suffix .. "}",verbose)
  if (rpm.expand("%{?forgesource" .. suffix .. "}") ~= "") then
    fedora.safeset("gosource" .. suffix, "%{forgesource" .. suffix .. "}",verbose)
  else
    fedora.safeset("gosource" .. suffix, "%{gourl" .. suffix .. "}/%{archivename" .. suffix .. "}.%{archiveext" .. suffix .. "}",verbose)
  end
  fedora.safeset(  "goname"   .. suffix, rpmname("%{goipath" .. suffix .. "}", "%{?gocid" .. suffix .. "}")                     ,verbose)
  fedora.zalias({"forgeurl","goname","gourl","gosource"},verbose)
  -- Final spec variable summary if the macro was called with -i
  if informative then
    rpm.expand("%{echo:Packaging variables read or set by %%gometa}")
    fedora.echovars({"goipath","goname","gourl","gosource"}, suffix)
  end
end

-- Pivot variable definitions for each kind of Go package
local pivot = {devel = "goipaths", alt = "goaltipaths"}

-- Default argument flag for each kind of list
local listflags = {goipaths = "-i", goipathsex = "-t", goextensions = "-e"}

-- Convert a space-separated list of import paths to a table indexed by their
-- rpmname version, to handle upstreams that play naming games
local function indexedgoipaths(goipaths, gocid)
  local       go = require "fedora.srpm.go"
  local giptable = {}
  for goipath in string.gmatch(rpm.expand(goipaths), "[^%s,]+") do
    local key = go.rpmname(goipath, gocid)
    if (not string.match(key, "^compat-")) then
      key = "compat-" .. key
    end
    if (giptable[key] == nil) then
      giptable[key] = {}
    end
    table.insert(giptable[key], goipath)
  end
  return giptable
end

-- Create fallbacks to goipath variables if godevelipath variables are missing
local function develenvinit()
  local  fedora = require "fedora.common"
  if (next(fedora.getsuffixes("goipaths")) == nil) then
    for _, suffix in pairs(fedora.getsuffixes("goipath")) do
      fedora.safeset("goipaths" .. suffix, "%{goipath" .. suffix .. "}")
    end
  end
end

-- Set rpm variables related to the processing of a golang-*-devel subpackage
local function develenv(suffix, verbose)
  local fedora = require "fedora.common"
  local     go = require "fedora.srpm.go"
  local ismain = (suffix == "") or (suffix == "0")
  if ismain then
    fedora.zalias(  {"goipath", "gocid", "gofilelist",
                     "godevelname", "godevelcid", "godevelfilelist", "godevelsummary", "godeveldescription",
                     "godevelheader", "goextensions", "gosupfiles", "gosupfilesex",
                     "goipaths", "goipathsex", "golicenses", "golicensesex", "godocs", "godocsex"},           verbose)
  end
  for list, flag in pairs(listflags) do
    local l = rpm.expand("%{?" .. list .. suffix .. "}")
    if (l ~= "") then
      l = string.gsub(" " .. l, "%s+%" .. flag .. "%s+", " ")
      l = string.gsub(l, "%s+", " ")
      l = string.gsub(l, "^ ", "")
      l = string.gsub(l, " $", "")
      if (list ~= "goipaths") then
        l = string.gsub(l, "([^%s]+)", flag .. " %1")
      end
      fedora.explicitset(list .. suffix, l)
    end
  end
  local  goipaths = rpm.expand("%{?goipaths" .. suffix .. "}")
  local   goipath = string.match(goipaths, "[^%s]+")
  fedora.safeset("godevelcid"         .. suffix, "%{?gocid"       .. suffix .. "}",                           verbose)
  local   rpmname = go.rpmname(goipath,           "%{?godevelcid" .. suffix .. "}")
  fedora.safeset("godevelname"        .. suffix, rpmname .. "-devel",                                         verbose)
  fedora.safeset("godevelfilelist"    .. suffix, rpmname .. "-%{gofilelist}",                                 verbose)
  fedora.safeset("godevelsummary"     .. suffix, "%{summary}",                                                verbose)
  fedora.safeset("godeveldescription" .. suffix, "%{?common_description}",                                    verbose)
  local postdescr = "\n\nThis package contains the source code needed for building packages that reference " ..
                    "the following Go import paths:"
  postdescr       = postdescr .. string.gsub(goipaths, "([^%s]+)", "\n – %1")
  fedora.explicitset("currentgodeveldescription", "%{expand:%{godeveldescription" .. suffix .. "}" ..
                                                  postdescr .. "}",                                           verbose)
  fedora.setcurrent({"godevelname", "godevelcid", "godevelfilelist", "godevelsummary",
                     "godevelheader", "goextensions", "gosupfiles", "gosupfilesex",
                     "goipaths", "goipathsex", "golicenses", "golicensesex", "godocs", "godocsex"}, suffix,   verbose)
  if ismain then
    fedora.zalias(  {"godevelname", "godevelcid", "godevelfilelist", "godevelsummary", "godeveldescription"}, verbose)
  end
end

-- Set rpm variables related to the processing of a compat-golang-*-devel subpackage
local function altenv(suffix, rpmname, goaltipaths, verbose)
  local fedora = require "fedora.common"
  local     go = require "fedora.srpm.go"
  local ismain = (suffix == "") or (suffix == "0")
  if ismain then
    fedora.zalias(  {"goipath", "gocanonipath",
                     "goaltdescription", "goaltsummary", "goaltheader"},                                      verbose)
  end
  fedora.safeset("gocanonipath"     .. suffix,    "%{goipath" .. suffix .. "}",                               verbose)
  fedora.safeset("goaltsummary"     .. suffix,    "%{summary}",                                               verbose)
  fedora.safeset("goaltdescription" .. suffix,    "%{?common_description}",                                   verbose)
  fedora.setcurrent( {"gocanonipath", "goaltcid", "goaltsummary"}, suffix,                                    verbose)
  local postdescr = "\n\nThis package provides symbolic links that alias the following Go import paths "   ..
                    "to %{currentgocanonipath}:"
  local  posthead = ""
  for _, goaltipath in ipairs(goaltipaths) do
    postdescr     = postdescr .. "\n – " .. goaltipath
    posthead      = "\nObsoletes: " .. go.rpmname(goaltipath, "") .. "-devel < %{version}-%{release}"
  end
  postdescr       = postdescr ..
                    "\n\nAliasing Go import paths via symbolic links or http redirects is fragile. " ..
                        "If your Go code depends on this package, you should patch it to import "   ..
                        "directly %{currentgocanonipath}."
  fedora.explicitset("currentgoaltdescription", "%{expand:%{?goaltdescription" .. suffix .. "}" ..
                                                   postdescr .. "}",                                          verbose)
  fedora.explicitset("currentgoaltheader",      "%{expand:%{?goaltheader" .. suffix .. "}"      ..
                                                   posthead  .. "}",                                          verbose)
  fedora.explicitset("currentgoaltname",        rpmname .. "-devel",                                          verbose)
  fedora.explicitset("currentgoaltfilelist",    rpmname .. "-%{gofilelist}",                                  verbose)
  if ismain then
    fedora.zalias(  {"gocanonipath", "goaltsummary", "goaltdescription"},                                     verbose)
  end
end

-- Create a single %package section for a known kind of Go subpackage
local function singlepkg(kind, suffix, verbose)
  local fedora = require "fedora.common"
  if     (kind == "devel")  then
    develenv(suffix, verbose)
    print(
      rpm.expand(
        "%package     -n %{currentgodevelname}\n" ..
        "Summary:        %{currentgodevelsummary}\n" ..
        "BuildRequires:  go-rpm-macros\n" ..
        "BuildArch:      noarch\n" ..
        "%{?currentgodevelheader}\n" ..
        "%description -n %{currentgodevelname}\n") ..
      fedora.wordwrap("%{?currentgodeveldescription}") ..
      "\n")
  elseif (kind == "alt") then
    local ismain = (suffix == "") or (suffix == "0")
    if ismain then
      fedora.zalias({"goaltipaths","gocid","goaltcid"},                verbose)
    end
    fedora.safeset("goaltcid" .. suffix, "%{?gocid"  .. suffix .. "}", verbose)
    if ismain then
      fedora.zalias({"goaltcid"},                                      verbose)
    end
    for rpmname, goaltipaths in pairs(indexedgoipaths("%{goaltipaths" .. suffix .. "}",
                                                      "%{goaltcid"    .. suffix .. "}")) do
      altenv(suffix, rpmname, goaltipaths, verbose)
      print(
        rpm.expand(
          "%package     -n %{currentgoaltname}\n" ..
          "Summary:        %{currentgoaltsummary}\n" ..
          "BuildRequires:  go-rpm-macros\n" ..
          "BuildArch:      noarch\n" ..
          "%{?currentgoaltheader}\n" ..
          "%description -n %{currentgoaltname}\n") ..
        fedora.wordwrap("%{?currentgoaltdescription}") ..
        "\n")
    end
  else
    rpm.expand("%{error:Unknown kind of Go subpackage: " .. kind .. "}")
  end
end

-- Create one or all %package sections for a known kind of go subpackage
local function pkg(kind, suffix, processall, verbose)
  local fedora = require "fedora.common"
  if (kind == "devel") then
    develenvinit()
  end
  if processall then
    for _, suffix in pairs(fedora.getsuffixes(pivot[kind])) do
       singlepkg(kind, suffix, verbose)
    end
  else
    singlepkg(kind, suffix, verbose)
  end
end

-- Create a single %files section for a known kind of Go subpackage
local function singlefiles(kind, suffix, verbose)
  if     (kind == "devel")  then
    develenv(suffix, verbose)
    print(rpm.expand('%files -n %{currentgodevelname}    -f "%{goworkdir}/%{currentgodevelfilelist}"\n'))
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
    for rpmname, goaltipaths in pairs(indexedgoipaths("%{goaltipaths" .. suffix .. "}",
                                                      "%{goaltcid"    .. suffix .. "}")) do
      altenv(suffix, rpmname, goaltipaths, verbose)
      print(rpm.expand('%files -n %{currentgoaltname} -f "%{goworkdir}/%{currentgoaltfilelist}"\n'))
    end
  else
    rpm.expand("%{error:Unknown kind of Go subpackage: " .. kind .. "}")
  end
end

-- Create one or all %files sections for a known kind of go subpackage
local function files(kind, suffix, processall, verbose)
  local fedora = require "fedora.common"
  if (kind == "devel") then
    develenvinit()
  end
  if processall then
    for _, suffix in pairs(fedora.getsuffixes(pivot[kind])) do
       singlefiles(kind, suffix, verbose)
    end
  else
    singlefiles(kind, suffix, verbose)
  end
end

return {
  rpmname         = rpmname,
  meta            = meta,
  pivot           = pivot,
  indexedgoipaths = indexedgoipaths,
  develenvinit    = develenvinit,
  develenv        = develenv,
  altenv          = altenv,
  pkg             = pkg,
  files           = files,
}
