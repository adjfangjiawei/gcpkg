#ifndef GCPKG_BUILDSYSTEMANALYSIS_H
#define GCPKG_BUILDSYSTEMANALYSIS_H

#include "MainProcess/DependenciesAnalysis.h"  // For BuildPlan
#include "toml++/toml.hpp"

namespace MainProcess {

    void ApplyExportedBuildSystem(BuildPlan& plan,
                                  toml::table& build_configs,
                                  const toml::table& port_toml,
                                  std::map<std::string, std::string>& variables);

}  // namespace MainProcess

#endif  // GCPKG_BUILDSYSTEMANALYSIS_H