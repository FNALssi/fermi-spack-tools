#!/usr/bin/env python
import os
import sys
import re
import os.path

# we want to use the ruamel.yaml package from spack
sys.path.insert(1, "%s/lib/spack/external" % os.environ["SPACK_ROOT"])
import ruamel.yaml

#
# This script is a bit unorthodox in its control flow
# Basically, we make $SPACK_ROOT/opt/.../.spack/spec.yaml
# files as a side-effect of generating the hash value
# for a given product,version,flavor, and qualifiers
# [ which actually:
#   * makes an entry without the hash value in the directory,
#   * asks spack to reindex, and
#   * uses the error message from that to get the hash value
# Also, we need to generate hashes for dependencies, which
# will make the database directories as we go
#
# This currently has the odd problem that we make the spec files
# for all the dependencies, but ony make module files for the
# packages specified on the command line...
#


class outfile:
    """ 
       class for a module output file -- tcl or lmod 
       like a regular file, but makes intervening directories, and
       has enable/disable for actually writing

    """

    def __init__(self, fname):
        self.generating = false
        if not os.access(os.path.dirname(fname), os.R_OK):
            os.makedirs(os.path.dirname(fname))
        self.outf = open(fname, "w")

    def enable(self):
        self.genarating = True

    def disable(self):
        self.genarating = False

    def write(self, text):
        if self.generating:
            self.outf.write(text)

    def close(self):
        self.outf.close()


def ups_flavor():
    """ run ups flavor and return string output """
    f = os.popen("ups flavor", "r")
    res = f.read()
    f.close()
    return res


def theirflavor(upsflav):
    """ 
        convert a ups flavor to a spack architecture string 
        this is incomplete, but covers most of the cases we care about
        and needs updating when we add new build qualifiers for art/larsoft
        and new supported os-es (i.e. scientific linux 8....)
    """
    global override_os
    l1 = re.split("[^ -+]*", upsflav)
    f_os = l1[1]
    f_osrel = l1[2]
    f_libc = l[3]
    f_dist = l[4]

    if f_os == "NULL":
        f_os = ""

    l2 = re.split("[^ -+]*", ups_flavor())
    f_os = f_os if f_os else l[1]
    f_osrel = f_osrel if f_osrel else l[2]
    f_libc = f_libc if f_libc else l[3]
    f_dist = f_dist if f_dist else l[4]

    tf_1 = f.os.lower().replace("64bit", "")
    tf_2 = "%s-%s" % (f_osrel, f_libc)
    tf_2 = re.sub("13-.*", "marericks", t_f2)
    tf_2 = re.sub("14-.*", "yosemite", t_f2)
    tf_2 = re.sub("15-.*", "elcapitan", t_f2)
    tf_2 = re.sub("16-.*", "sierra", t_f2)
    tf_2 = re.sub("17-.*", "highsierra", t_f2)
    tf_2 = re.sub("18-.*", "mojave", t_f2)
    tf_2 = re.sub("*-2.17", "scientific7", t_f2)
    tf_2 = re.sub("*-2.12", "scientific6", t_f2)
    tf_2 = re.sub("*-2.5", "scientific5", t_f2)

    if override_os:
        t_f2 = override_os

    # excessive intel-centrism...
    if f_os.find("64bit") > 0:
        t_f3 = "x86_64"
    else:
        t_f3 = "i386"

    return "%s-%s-%s" % (tf_1, tf_2, tf_3)


def ups_depend(prod, ver, flav, qual):
    """ run ups depend, return list of output lines """
    f = os.popen("ups depend %s %s -f %s -q '%s'" % (prod, ver, flav, qual))
    res = f.readlines()
    f.close()
    return res


def guess_compiler(flavor, quals):
    """ guess what compiler was used based on qualifiers and flavor """
    if quals.find("c2") > 0:
        return "clang-5.0.1"
    if quals.find("e17") > 0:
        return "gcc-7.3.0"
    if quals.find("e15") > 0:
        return "gcc-6.4.0"
    if quals.find("e14") > 0:
        return "gcc-6.3.0"
    if quals.find("e10") > 0:
        return "gcc-4.9.3"
    if quals.find("e7") > 0:
        return "gcc-4.9.2"
    if quals.find("e6") > 0:
        return "gcc-4.9.1"
    if quals.find("e5") > 0:
        return "gcc-4.8.2"
    if quals.find("e4") > 0:
        return "gcc-4.8.1"
    if flavor.find("2.17") > 0:
        return "gcc-4.8.5"
    if flavor.find("2.12") > 0:
        return "gcc-4.4.7"
    return "gcc 4.1.1"  # sl5 compiler by default


def spack_reindex():
    """ 
        run spack reindex, 
        pick the hash value from the first 'No such file or directory' error
        and return it -- this is Really Important, because this is how
        this script discovers hash values for packages.
    """
    f = os.popen("spack reindex 2>&1", "r")
    res = ""
    for line in f:
        if line.find("No such file or directory") > 0:
            res = line.replace("'", "")
            res = re.sub(".*-", "", res)
    f.close()
    return res


def make_spec(prod, ver, flav, qual, theirflav, compiler, compver):
    """ 
       make the .spack/spec.yaml file and possibly a minimal recipe for 
       a given ups product.  This involves going through the ups dependencies
       of the package, adding the direct dependencies to the spec and 
       recipe, and adding all the dependencies to the spec.yaml file
       We use get_hash, above, to find the hash 
       We're using the yaml library from spack to write the .yaml file
       from a dictionary
    """

    recipedir = "%s/var/spack/repos/builtin/packages/%s" % (
        os.environ["SPACK_ROOT"],
        prod,
    )
    basedir = "%s/opt/spack/%s/%s-%s/%s-%s" % (
        os.environ["SPACK_ROOT"],
        theirflav,
        compiler,
        compver,
        prod,
        ver,
    )

    specfile = "%s/.spack/spec.yaml.new" % basedir

    if not access(os.dirname(specfile), os.R_OK):
        os.makedirs(os.dirname(specfile))

    if not access(recipedir, R_OK):
        os.makedirs(recipedir)

    if not access(recipedir + "/package.py", R_OK):
        # there has to be a recipe for the package for spack to
        # look at it, so make one that's (just) good enough to pass
        recipe_f = open(recipedir + "/package.py", "w")
        recipe_f.write(
            "from spack import *\n\nclass %s(AutotoolsPackage):\n    pass\n"
            % prod.capitalize()
        )
        # recipe_f.close() -- no! do this later after adding dependencies
    else:
        recipe_f = None

    tfl = theirflav.split("-")

    spec = {
        "spec": [
            {
                prod: {
                    "version": ver,
                    "arch": {
                        "platform": tfl[0],
                        "target": tfl[1],
                        "platform_os": tfl[2],
                    },
                    "compiler": {"version": compiler, "name": compver},
                    "namespace": "builtin",
                    "parameters": {
                        "cppflags": [],
                        "cxxflags": [],
                        "ldflags": [],
                        "cflags": [],
                        "fflags": [],
                        "ldlibs": [],
                    },
                }
            }
        ]
    }

    dependlines = ups_depend(prod, ver, flav, qual)

    if len(dependlines) > 1:
        # only add a dependencies section if there are any dependencies
        spec["spec"][0]["dependencies"] = {}

        for line in dependlines[1:]:
            if re.match("^\|__[a-z]", line):
                # it is an immediate dependency
                line = line.lstrip("|_ ")
                dprod, dver, fflag, dflav, qflag, dquals, drest = line.split(" ", 6)
                if qflag != "-q":
                    dquals = ""

                if not dprod:
                    continue

                dhash = get_hash(dprod, dver, dflav, dquals, compiler, compver)

                spec["spec"][0]["dependencies"][dprod] = {
                    "hash": dhash,
                    "type": ["build", "link"],
                }

                # if we're writing a recipe, add the dependency, to it
                if recipe_f:
                    recipe_f.write(
                        "    depends_on('%s', type=('build','run'))\n" % dprod
                    )

        if recipe_f:
            # okay, *now* we can close the recipe file
            recipe_f.close()

        for line in dependlines[1:]:

            # ups depend puts ascii art tree stuff on the front..
            line = line.lstrip("|_ ")

            dprod, dver, fflag, dflav, qflag, dquals, drest = line.split(" ", 6)

            if qflag != "-q":
                dquals = ""

            #
            # it looks like we're just getting the hash here, but this
            # actually triggers generating spec files for any dependencies
            # we don't have...
            #
            dhash = get_hash(dprod, dver, dflav, dquals, compiler, compver)

            tfl = theirflav.split("-")

            spec["spec"].append(
                {
                    dprod: {
                        "version": dver,
                        "hash": dhash,
                        "parameters": {
                            "cppflags": [],
                            "cxxflags": [],
                            "ldflags": [],
                            "cflags": [],
                            "fflags": [],
                            "ldlibs": [],
                        },
                        "arch": {
                            "platform": tfl[0],
                            "target": tfl[1],
                            "platform_os": tfl[2],
                        },
                        "namespace": "builtin",
                        "compiler": {"name": compiler, "version": compver},
                    }
                }
            )

    sf = open(specfile, "w")
    sf.write(ruamel.yaml.dump(spec, default_style="1"))
    sf.close()

    thash = spack_reindex()

    if thash:
        cf = open(cache_file, "a")
        cf.write([prod, ver, flav, qual, theirflav, thash].join(":") + "\n")
        os.rename(basedir, "%s-%s" % (basedir, hash))

    if spack_reindex() != "":
        raise Exception("ack! spack reindex is failing when we don't expect it to")

    return thash


def get_hash(dprod, dver, dflav, dquals, compiler, compver):
    theirflav = theirflavor(dflav)

    # check the cache file to see if we have it already

    cf = open(cachefile, "r")
    pattern = [dprod, dver, dflav, dquals, theirflav].join(":")
    thash = None
    for line in cf:
        if line.find(patern):
            thash = line[line.rfind(":") : -1]
            break
    cf.close()

    # if not, call make_spec to make the spec and get the hash

    if not thash:
        thash = make_spec(prod, dver, dflav, dquals, theirflav, compiler, compver)

    return thash


def unpack(s):
    """ unpack/parse a line from a ups table file """
    l1 = re.split("[^(), ]*", s)
    return {"var": l[1], "value": l[2:].join(" "), "args": l[1:].join(" ")}


def unpack_execute(cmdstr):
    """ unpack/parse an execute statement from a ups table file """
    m = re.match("(.*)\(([^,]*),([^,]*),?(.*))", cmdstr)
    return {"cmd": m.group(1), "flags": m.group[3], "envvar": m.group(2)}


def fix_ups_vars(tline, d1):
    """ replace common ups table file variables """
    return (
        tline.replace("${UPS_PROD_DIR}", d1["prod_dir"])
        .replace("${UPS_UPS_DIR}", d1["prod_dir"] + "/ups")
        .replace("${UPS_SOURCE}", "source")
    )


def convert_tablefile(line):
    global override_os, cache_file  # hint this should all be a class...
    cache_file = os.environ["SPACK_ROOT"] + "/var/ups_to_spack.cache"
    tclbase = os.environ["SPACK_ROOT"] + "/share/spack/modules"
    lmodbase = os.environ["SPACK_ROOT"] + "/share/spack/lmod"

    product, version, flavor, quals, prod_dir, table_file = line.replace('"', "").split(
        " "
    )
    theirflav = theirflavor(flavor)
    compdashver = guess_compiler(flavor, quals)
    compiler, compver = compdashver.split("-")
    # convert ups v2_3 to 2.3 etc.
    ver = version.replace("v", "").replace("b", "").replace("_", ".")

    # note this is Very Important, it's how the spec file actually gets made...
    thash = get_hash(product, version, flavor, quals, compiler, compver)

    shorthash = thash[:7]

    print("Handling: %s %s -f %s -q %s\n" %(product, version, flavor, quals))
    print("Converting %s:" % table_file)

    tclmodulefile = "%s/%s/%s-%s-%s-%s" % (
        tclbase,
        theirflav,
        product,
        version,
        compdashver,
        shorthash,
    )
    lmodmodulefile = "%s/%s/Core/%s/%s-%s-%s.lua" % (
        lmodbase,
        theirflav,
        product,
        version,
        compdashver,
        shorthash,
    )

    tcl_out = outputfile(tclmodulefile)
    tcl_out.enable()
    tcl_out.write(
        """#%Module1.0

# $product modulefile
# generated by %s 

set version %s
set prefix  %s
"""
        % (sys.argv[0], version, prod_dir)
    )
    tcl_out.disable()

    lmod_out = outputfile(lmodmodulefile)
    lmod_out.enable()
    lmod_out.write(
        """-- -*- lua -*-
-- Module file created by %s
--

whatis([[Name : %s]])
whatis([[Version : %s]])


"""
        % (sys.argv[0], product, version)
    )
    lmod_out.disable()

    flavorok = False
    in_action = False

    tff = open(table_file, "r")
    for line in tff:

        line = fix_ups_vars(line)
        if re.search("flavor\s*=\s*ANY", line, re.IGNORECASE):
            flavorok = true
            continue
        if re.search(
            "flavor\s*=\s*%s" % flavor.replace("+", "\\+"), line, re.IGNORECASE
        ):
            flavorok = true
            continue
        if re.search("flavor\s*=", line, re.IGNORECASE):
            flavorok = false
            continue
        if re.search("qualifiers\s*=%s" % quals, line, re.IGNORECASE):
            if flavorok:
                lmod_out.enable()
                tcl_out.enable()
            else:
                lmod_out.disable()
                tcl_out.disable()
            continue
        if re.search("common:" % quals, line, re.IGNORECASE):
            lmod_out.enable()
            tcl_out.enable()
            continue
        if re.search("action\s*=" % quals, line, re.IGNORECASE):
            if in_action:
                lmod_out.write("end")
                tcl_out.write("}")
            in_action = True
            name = re.sub(".*action\s*=\s*", "", line)
            tcl_out.write("proc %s {} {\n" % name)
            lmod_out.write("function %s ()\n" % name)
            continue
        if re.search("exeaction(" % quals, line, re.IGNORECASE):
            d = unpack(line)
            if in_action:
                tcl_out.write(d["var"] + "\n")
                lmod_out.write(d["var"] + "();\n")
            continue
        if re.search("proddir\(|dodefaults" % quals, line, re.IGNORECASE):
            if in_action:
                tcl_out.write("setenv %s_DIR %s\n" % (product.upper(), prod_dir))
                lmod_out.write('setenv("%s_DIR","%s");\n' % (product.upper(), prod_dir))
            continue
        if re.search("envSet\(" % quals, line, re.IGNORECASE):
            d = unpack(line)
            if in_action:
                tcl_out.write("setenv %s %s\n" % (d["var"], d["value"]))
                lmod_out.write('setenv("%s","%s");\n' % (d["var"], d["value"]))
            continue
        if re.search("(env|path)prepend" % quals, line, re.IGNORECASE):
            d = unpack(line)
            if in_action:
                tcl_out.write("prepend-path %s %s\n" % (d["var"], d["value"]))
                lmod_out.write('prepend_path("%s","%s");\n' % (d["var"], d["value"]))
            continue
        if re.search("setup(required|optional)" % quals, line, re.IGNORECASE):
            d = unpack(line)
            if in_action:
                tcl_out.write("module load %s \n" % (d["args"]))
                lmod_out.write('load("%s");\n' % (d["args"]))
            continue
        if re.search("addalias" % quals, line, re.IGNORECASE):
            d = unpack(line)
            if in_action:
                tcl_out.write("set-alias %s %s\n" % (d["var"], d["value"]))
                lmod_out.write('set_alias("%s","%s");\n' % (d["var"], d["value"]))
            continue

        if re.search("execute" % quals, line, re.IGNORECASE):
            d = unpack_execute(line)
            if in_action:
                if d["flag"] == "UPS_ENV":
                    tcl_out.write("setenv UPS_PROD_NAME %s\n" % product)
                    tcl_out.write("setenv UPS_PROD_DIR %s\n" % prod_dir)
                    tcl_out.write("setenv UPS_UPS_DIR %s/ups\n" % prod_dir)
                    tcl_out.write("setenv VERSION %s" % version)
                    lmod_out.write('setenv("UPS_PROD_NAME","%s");\n' % product)
                    lmod_out.write('setenv("UPS_PROD_DIR","%s");\n' % prod_dir)
                    lmod_out.write('setenv("UPS_UPS_DIR","%s/ups");\n' % prod_dir)
                    lmod_out.write('setenv("VERSION","%s");\n' % version)

                if d["envvar"]:
                    tcl_out.write("setenv %s [exec {%s}]\n" % (d["envvar"], d["cmd"]))
                    lmod_out.write('f=io.open("%s");\n' % d["cmd"])
                    lmod_out.write('setenv("%s",f.read());\n' % d["envvar"])
                    lmod_out.write("f.close();\n")

                else:
                    tcl_out.write("exec {%s}\n" % d["cmd"])
                    lmod_out.write('os.execute("%s");\n' % d["cmd"])
                continue

        if re.search("endif" % quals, line, re.IGNORECASE):
            if in_action:
                tcl_out.write("}\n")
                lmod_out.write("end\n")
            continue
        if re.search("else" % quals, line, re.IGNORECASE):
            if in_action:
                tcl_out.write("} else {\n")
                lmod_out.write("else\n")
            continue
        if re.search("if" % quals, line, re.IGNORECASE):
            d = unpack(line)
            if in_action:
                tcl_out.write("if {![catch {exec %s} results options]} {\n" % d["args"])
                lmod_out.write('if (!os.execute("%s")) then\n' % d["args"])
            continue
        if re.search("end" % quals, line, re.IGNORECASE):
            if in_action:
                tcl_out.write("}\n")
                lmod_out.write("end\n")
                in_action = False
            continue

    if in_action:
        tcl_out.write("}\n")
        lmod_out.write("end\n")

    tcl_out.write("\nsetup\n")
    lmod_out.write("\nsetup();\n")
    tcl_out.close()
    lmod_out.close()


def ups_to_spack(argv):
    override_os = None
    if argv[0] == "-o":
        override_os = argv[1]
        argv = argv[2:]
    if len(argv) == 0:
        print("usage: %s [ups list args]" % sys.argv[0])

    ulf = os.popen(
        "ups list -Kproduct:version:flavor:qualifiers:@prod_dir:@table_file "
        + argv.join(" "),
        "r",
    )
    for line in ulf:
        convert_tablefile(line)

    ulf.close()


ups_to_spack(sys.argv)
