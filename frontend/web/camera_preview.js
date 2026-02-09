// Camera preview for web — manages a <video> element with getUserMedia
(function () {
  let _stream = null;
  let _videoEl = null;

  window.cameraPreview = {
    // Called from Dart's platform view factory to store the video element reference.
    // This avoids getElementById which fails in Flutter's shadow DOM.
    setVideoElement: function (el) {
      _videoEl = el;
      // If stream was already acquired, attach it immediately
      if (_stream && _videoEl) {
        _videoEl.srcObject = _stream;
        _videoEl.play().catch(function () {});
      }
    },

    start: async function (elementId) {
      try {
        _stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: 'user', width: 320, height: 240 },
          audio: false,
        });

        // Prefer element set by Dart factory; fallback to getElementById
        if (!_videoEl) {
          _videoEl = document.getElementById(elementId);
        }

        if (_videoEl) {
          _videoEl.srcObject = _stream;
          _videoEl.muted = true;
          await _videoEl.play();
        }

        return true;
      } catch (e) {
        console.error('Camera start error:', e);
        return false;
      }
    },

    stop: function () {
      if (_stream) {
        _stream.getTracks().forEach(function (t) { t.stop(); });
        _stream = null;
      }
      if (_videoEl) {
        _videoEl.srcObject = null;
      }
    },

    getVideoElement: function () {
      return _videoEl;
    },

    captureFrame: function (quality) {
      if (!_videoEl || !_stream) return null;
      try {
        var canvas = document.createElement('canvas');
        canvas.width = _videoEl.videoWidth || 320;
        canvas.height = _videoEl.videoHeight || 240;
        canvas.getContext('2d').drawImage(_videoEl, 0, 0, canvas.width, canvas.height);
        var dataUrl = canvas.toDataURL('image/jpeg', quality || 0.7);
        return dataUrl.split(',')[1]; // return base64 only
      } catch (e) {
        console.error('Frame capture error:', e);
        return null;
      }
    },
  };
})();
