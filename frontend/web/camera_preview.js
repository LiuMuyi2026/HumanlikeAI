// Camera preview for web — manages a <video> element with getUserMedia
(function () {
  let _stream = null;
  let _videoEl = null;

  window.cameraPreview = {
    start: async function (elementId) {
      try {
        _stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: 'user', width: 320, height: 240 },
          audio: false,
        });

        _videoEl = document.getElementById(elementId);
        if (!_videoEl) {
          _videoEl = document.createElement('video');
          _videoEl.id = elementId;
          _videoEl.style.position = 'fixed';
          _videoEl.style.top = '-9999px';
          _videoEl.style.left = '-9999px';
          document.body.appendChild(_videoEl);
        }

        _videoEl.srcObject = _stream;
        _videoEl.setAttribute('autoplay', '');
        _videoEl.setAttribute('playsinline', '');
        _videoEl.muted = true;
        await _videoEl.play();
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
  };
})();
