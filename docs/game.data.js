
  var Module = typeof Module != 'undefined' ? Module : {};

  if (!Module['expectedDataFileDownloads']) Module['expectedDataFileDownloads'] = 0;
  Module['expectedDataFileDownloads']++;
  (() => {
    // Do not attempt to redownload the virtual filesystem data when in a pthread or a Wasm Worker context.
    var isPthread = typeof ENVIRONMENT_IS_PTHREAD != 'undefined' && ENVIRONMENT_IS_PTHREAD;
    var isWasmWorker = typeof ENVIRONMENT_IS_WASM_WORKER != 'undefined' && ENVIRONMENT_IS_WASM_WORKER;
    if (isPthread || isWasmWorker) return;
    async function loadPackage(metadata) {

      var PACKAGE_PATH = '';
      if (typeof window === 'object') {
        PACKAGE_PATH = window['encodeURIComponent'](window.location.pathname.substring(0, window.location.pathname.lastIndexOf('/')) + '/');
      } else if (typeof process === 'undefined' && typeof location !== 'undefined') {
        // web worker
        PACKAGE_PATH = encodeURIComponent(location.pathname.substring(0, location.pathname.lastIndexOf('/')) + '/');
      }
      var PACKAGE_NAME = 'game.data';
      var REMOTE_PACKAGE_BASE = 'game.data';
      var REMOTE_PACKAGE_NAME = Module['locateFile'] ? Module['locateFile'](REMOTE_PACKAGE_BASE, '') : REMOTE_PACKAGE_BASE;
      var REMOTE_PACKAGE_SIZE = metadata['remote_package_size'];

      async function fetchRemotePackage(packageName, packageSize) {
        
        if (!Module['dataFileDownloads']) Module['dataFileDownloads'] = {};
        try {
          var response = await fetch(packageName);
        } catch (e) {
          throw new Error(`Network Error: ${packageName}`, {e});
        }
        if (!response.ok) {
          throw new Error(`${response.status}: ${response.url}`);
        }

        const chunks = [];
        const headers = response.headers;
        const total = Number(headers.get('Content-Length') || packageSize);
        let loaded = 0;

        Module['setStatus'] && Module['setStatus']('Downloading data...');
        const reader = response.body.getReader();

        while (1) {
          var {done, value} = await reader.read();
          if (done) break;
          chunks.push(value);
          loaded += value.length;
          Module['dataFileDownloads'][packageName] = {loaded, total};

          let totalLoaded = 0;
          let totalSize = 0;

          for (const download of Object.values(Module['dataFileDownloads'])) {
            totalLoaded += download.loaded;
            totalSize += download.total;
          }

          Module['setStatus'] && Module['setStatus'](`Downloading data... (${totalLoaded}/${totalSize})`);
        }

        const packageData = new Uint8Array(chunks.map((c) => c.length).reduce((a, b) => a + b, 0));
        let offset = 0;
        for (const chunk of chunks) {
          packageData.set(chunk, offset);
          offset += chunk.length;
        }
        return packageData.buffer;
      }

      var fetchPromise;
      var fetched = Module['getPreloadedPackage']?.(REMOTE_PACKAGE_NAME, REMOTE_PACKAGE_SIZE);

      if (!fetched) {
        // Note that we don't use await here because we want to execute the
        // the rest of this function immediately.
        fetchPromise = fetchRemotePackage(REMOTE_PACKAGE_NAME, REMOTE_PACKAGE_SIZE);
      }

    async function runWithFS(Module) {

      function assert(check, msg) {
        if (!check) throw new Error(msg);
      }
Module['FS_createPath']("/", "assets", true, true);
Module['FS_createPath']("/assets", "shaders", true, true);

      for (var file of metadata['files']) {
        var name = file['filename']
        Module['addRunDependency'](`fp ${name}`);
      }

      async function processPackageData(arrayBuffer) {
        assert(arrayBuffer, 'Loading data file failed.');
        assert(arrayBuffer.constructor.name === ArrayBuffer.name, 'bad input to processPackageData ' + arrayBuffer.constructor.name);
        var byteArray = new Uint8Array(arrayBuffer);
        var curr;
        // Reuse the bytearray from the XHR as the source for file reads.
          for (var file of metadata['files']) {
            var name = file['filename'];
            var data = byteArray.subarray(file['start'], file['end']);
            // canOwn this data in the filesystem, it is a slice into the heap that will never change
          Module['FS_createDataFile'](name, null, data, true, true, true);
          Module['removeRunDependency'](`fp ${name}`);
          }
          Module['removeRunDependency']('datafile_game.data');
      }
      Module['addRunDependency']('datafile_game.data');

      if (!Module['preloadResults']) Module['preloadResults'] = {};

      Module['preloadResults'][PACKAGE_NAME] = {fromCache: false};
      if (!fetched) {
        fetched = await fetchPromise;
      }
      processPackageData(fetched);

    }
    if (Module['calledRun']) {
      runWithFS(Module);
    } else {
      if (!Module['preRun']) Module['preRun'] = [];
      Module['preRun'].push(runWithFS); // FS is not initialized yet, wait for it
    }

    }
    loadPackage({"files": [{"filename": "/assets/DejaVuSans.ttf", "start": 0, "end": 756072}, {"filename": "/assets/brain.ms", "start": 756072, "end": 874623}, {"filename": "/assets/console.ms", "start": 874623, "end": 885275}, {"filename": "/assets/display.ms", "start": 885275, "end": 908189}, {"filename": "/assets/geometry.ms", "start": 908189, "end": 915670}, {"filename": "/assets/icl.ms", "start": 915670, "end": 939160}, {"filename": "/assets/irregularPlurals.txt", "start": 939160, "end": 941843}, {"filename": "/assets/lexicon.ms", "start": 941843, "end": 972453}, {"filename": "/assets/listUtil.ms", "start": 972453, "end": 991408}, {"filename": "/assets/main.ms", "start": 991408, "end": 997132}, {"filename": "/assets/mathUtil.ms", "start": 997132, "end": 1032759}, {"filename": "/assets/meaning.ms", "start": 1032759, "end": 1061031}, {"filename": "/assets/parser.ms", "start": 1061031, "end": 1135330}, {"filename": "/assets/planner.ms", "start": 1135330, "end": 1149077}, {"filename": "/assets/relations.ms", "start": 1149077, "end": 1164167}, {"filename": "/assets/scenes.ms", "start": 1164167, "end": 1168258}, {"filename": "/assets/sessionLog.ms", "start": 1168258, "end": 1170859}, {"filename": "/assets/shaders/lit.fs", "start": 1170859, "end": 1171629}, {"filename": "/assets/shaders/lit.vs", "start": 1171629, "end": 1172121}, {"filename": "/assets/speech.ms", "start": 1172121, "end": 1185703}, {"filename": "/assets/stringUtil.ms", "start": 1185703, "end": 1206959}, {"filename": "/assets/textInput.ms", "start": 1206959, "end": 1219287}, {"filename": "/assets/uiText.ms", "start": 1219287, "end": 1222759}, {"filename": "/assets/world.ms", "start": 1222759, "end": 1243918}], "remote_package_size": 1243918});

  })();
