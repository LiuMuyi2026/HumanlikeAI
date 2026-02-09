// Web audio recorder using getUserMedia + ScriptProcessorNode
// Captures PCM 16kHz mono Int16 audio, stores as base64 chunks for Dart polling
class AudioRecorderWeb {
  constructor() {
    this.stream = null;
    this.context = null;
    this.processor = null;
    this.source = null;
    this.chunks = [];
    this.recording = false;
    this.targetRate = 16000;
  }

  async start() {
    // Clean up any previous session
    this._cleanup();

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        },
        video: false,
      });

      // Let browser choose native sample rate for best compatibility
      this.context = new AudioContext();
      const nativeRate = this.context.sampleRate;
      console.log('AudioRecorder: native sample rate =', nativeRate, 'target =', this.targetRate);

      this.source = this.context.createMediaStreamSource(this.stream);

      // ScriptProcessorNode: 4096 buffer, 1 input, 1 output
      this.processor = this.context.createScriptProcessor(4096, 1, 1);
      this.processor.onaudioprocess = (e) => {
        if (!this.recording) return;
        const inputData = e.inputBuffer.getChannelData(0);

        // Downsample if needed
        let float32;
        if (nativeRate !== this.targetRate) {
          const ratio = nativeRate / this.targetRate;
          const newLength = Math.floor(inputData.length / ratio);
          float32 = new Float32Array(newLength);
          for (let i = 0; i < newLength; i++) {
            float32[i] = inputData[Math.floor(i * ratio)];
          }
        } else {
          float32 = inputData;
        }

        // Convert Float32 to Int16
        const int16 = new Int16Array(float32.length);
        for (let i = 0; i < float32.length; i++) {
          const s = Math.max(-1, Math.min(1, float32[i]));
          int16[i] = s < 0 ? s * 0x8000 : s * 0x7FFF;
        }

        // Base64 encode the Int16 buffer
        const uint8 = new Uint8Array(int16.buffer);
        let binary = '';
        for (let i = 0; i < uint8.length; i++) {
          binary += String.fromCharCode(uint8[i]);
        }
        this.chunks.push(btoa(binary));
      };

      this.source.connect(this.processor);
      this.processor.connect(this.context.destination);
      this.recording = true;
      console.log('AudioRecorder: started');
      return true;
    } catch (e) {
      console.error('AudioRecorder start error:', e);
      this._cleanup();
      return false;
    }
  }

  _cleanup() {
    this.recording = false;
    if (this.processor) {
      try { this.processor.disconnect(); } catch(e) {}
      this.processor = null;
    }
    if (this.source) {
      try { this.source.disconnect(); } catch(e) {}
      this.source = null;
    }
    if (this.stream) {
      try { this.stream.getTracks().forEach(t => t.stop()); } catch(e) {}
      this.stream = null;
    }
    if (this.context && this.context.state !== 'closed') {
      try { this.context.close(); } catch(e) {}
      this.context = null;
    }
    this.chunks = [];
  }

  stop() {
    this._cleanup();
    console.log('AudioRecorder: stopped');
  }

  // Called by Dart to drain accumulated audio chunks
  drainChunks() {
    if (this.chunks.length === 0) return '[]';
    const result = JSON.stringify(this.chunks);
    this.chunks = [];
    return result;
  }

  isRecording() {
    return this.recording;
  }
}

window._audioRecorderInstance = new AudioRecorderWeb();

// Wrapper functions for Dart JS interop
window.recorderStart = async function() {
  try {
    return await window._audioRecorderInstance.start();
  } catch (e) {
    console.error('recorderStart error:', e);
    return false;
  }
};

window.recorderStop = function() {
  try {
    window._audioRecorderInstance.stop();
  } catch (e) {
    console.error('recorderStop error:', e);
  }
};

window.recorderDrainChunks = function() {
  try {
    return window._audioRecorderInstance.drainChunks();
  } catch (e) {
    console.error('recorderDrainChunks error:', e);
    return '[]';
  }
};

window.recorderIsRecording = function() {
  try {
    return window._audioRecorderInstance.isRecording();
  } catch (e) {
    return false;
  }
};
