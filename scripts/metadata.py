import io
import yaml
from datetime import datetime

import renewablepotentialslib


def metadata(config, version, path_to_output):
    metadata = {
        "description":
            "This is the metadata of the build process of "
            "the solar-and-wind-potentials model in the same directory.",
        "solar-and-wind-potentials-version": version,
        "renewable-potentials-lib-version": renewablepotentialslib.__version__,
        "generated-utc": datetime.utcnow(),
        "config": config
    }
    with io.open(path_to_output, 'w', encoding='utf8') as outfile:
        yaml.dump(metadata, outfile, default_flow_style=False, allow_unicode=True, sort_keys=False)


if __name__ == "__main__":
    metadata(
        config=snakemake.params.config,
        version=snakemake.params.version,
        path_to_output=snakemake.output[0]
    )
