
# we want to use the ruamel.yaml package from spack
import sys
sys.path.insert(1,"%s/lib/spack/external" % os.envrion("SPACK_ROOT"))
import ruamel.yaml

spec = {'spec': 
         [ 
           {
             'ifdhc': {
                'version': 'v2_3_0',
                'arch': {
                  'platform': 'linux',
                  'target': 'x86_64',
                  'platform_os': 'scientific7'
                },
                'parameters': {
                  'cppflags': [],
                  'cxxflags': [],
                  'ldflags': [],
                  'cflags': [],
                  'fflags': [],
                  'ldlibs': []
                },
             'dependencies': {
                'ifdhc_config': {
                  'hash': 'eutruet5el73wfusjulp47gvcovq34fb',
                  'type': '-build -link'
                },
                'awscli': {
                   'hash': 'afh2m34w4hg27yukbft766m6tnv2yi7r',
                   'type': '-build -link'
                },
                'cpn': {
                  'hash': 'ikgb3swjp5t3d5pgjbmkuauq52tigr67',
                  'type': '-build -link'
                }
              },
             'namespace': 'builtin',
             'compiler': {
               'version': '6.3.0',
               'name': 'gcc'
              }
            }
          },
          {'ifdhc_config': {
             'version': 'v2_4_5',
             'hash': 'eutruet5el73wfusjulp47gvcovq34fb',
             'parameters': {
               'cppflags': [],
               'cxxflags': [],
               'ldflags': [],
               'cflags': [],
               'fflags': [],
               'ldlibs': []
             },
             'arch': {
               'platform': 'linux',
               'target': 'x86_64',
               'platform_os': 'scientific7'
              },
             'namespace': 'builtin',
             'compiler': {
               'version': '6.3.0',
               'name': 'gcc'
              }
            }
          },
          {'cpn': {
             'version': 'v1.7',
             'hash': 'ikgb3swjp5t3d5pgjbmkuauq52tigr67',
             'parameters': {
               'cppflags': [],
               'cxxflags': [],
               'ldflags': [],
               'cflags': [],
               'fflags': [],
               'ldlibs': []
              },
             'arch': {
               'platform': 'linux',
               'target': 'x86_64',
               'platform_os': 'scientific7'
              },
             'namespace': 'builtin',
             'compiler': {
               'version': '6.3.0',
               'name': 'gcc'
              }
            }
          },
          {'awscli': {'version': 'v1_7_15',
             'hash': 'afh2m34w4hg27yukbft766m6tnv2yi7r',
             'parameters': {'cppflags': [],
             'cxxflags': [],
             'ldflags': [],
             'cflags': [],
             'fflags': [],
             'ldlibs': []
            },
             'arch': {'platform': 'linux',
             'target': 'x86_64',
             'platform_os': 'scientific7'
            },
             'namespace': 'builtin',
             'compiler': {'version': '6.3.0',
             'name': 'gcc'
            }
            }
           }
         ]
         }
print(ruamel.yaml.dump(y,default_style="1"))

