import docker
import docker.errors


class DockerManager(object):

    api = docker.APIClient(base_url="unix:///var/run/docker.sock")

    def get_image_layers(self, image):
        inspection = self.api.inspect_image(image)
        return inspection.get("RootFS").get("Layers")

    def is_parent_image_upgraded(self, image, parent_image):
        latest_parent_layer = self.get_image_layers(parent_image).pop()
        layers = self.get_image_layers(image)

        return latest_parent_layer not in layers

    def is_image_downloaded(self, image):
        try:
            self.api.inspect_image(image)
            return True
        except docker.errors.ImageNotFound:
            return False

    def pull_image(self, repository, tag):
        return self.api.pull(repository, tag)

    def build_image(self, cache_from, names, path=None):
        if not isinstance(names):
            names = [names]

        if path is None:
            path = "."

        self.api.build(cache_from=cache_from, tag=names[0], path=path, pull=True)
        if len(names) > 1:
            aliases = names[1:]
            for alias in aliases:
                repository, tag = alias.rsplit(":", 1) + [None]
                self.api.tag(names[0], repository, tag)