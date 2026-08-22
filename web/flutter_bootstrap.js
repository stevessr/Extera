{{flutter_js}}
{{flutter_build_config}}

// Start fetching the renderer and application as soon as this script is
// available. Waiting for window.load here would put every static page asset on
// the critical path to the first Flutter frame.
_flutter.loader.load({
  onEntrypointLoaded: async (engineInitializer) => {
    const appRunner = await engineInitializer.initializeEngine({
      useColorEmoji: true,
    });
    await appRunner.runApp();
  },
});
