// PCM audio player using Web Audio API
class PcmPlayer {
  constructor(sampleRate = 24000) {
    this.sampleRate = sampleRate;
    this.context = null;
    this.scheduledTime = 0;
    this.playing = false;
  }

  init() {
    if (!this.context) {
      this.context = new AudioContext({ sampleRate: this.sampleRate });
    }
    if (this.context.state === 'suspended') {
      this.context.resume();
    }
    this.scheduledTime = this.context.currentTime;
  }

  // Feed PCM 16-bit signed LE mono audio data
  feed(pcmBase64) {
    if (!this.context) this.init();
    // Always try to resume if suspended (Chrome autoplay policy)
    if (this.context.state === 'suspended') {
      this.context.resume();
    }

    const binaryString = atob(pcmBase64);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i);
    }

    // Convert Int16 PCM to Float32
    const int16 = new Int16Array(bytes.buffer);
    const float32 = new Float32Array(int16.length);
    for (let i = 0; i < int16.length; i++) {
      float32[i] = int16[i] / 32768.0;
    }

    // Create audio buffer
    const audioBuffer = this.context.createBuffer(1, float32.length, this.sampleRate);
    audioBuffer.getChannelData(0).set(float32);

    // Schedule playback
    const source = this.context.createBufferSource();
    source.buffer = audioBuffer;
    source.connect(this.context.destination);

    const now = this.context.currentTime;
    if (this.scheduledTime < now) {
      this.scheduledTime = now;
    }
    source.start(this.scheduledTime);
    this.scheduledTime += audioBuffer.duration;
    this.playing = true;
  }

  stop() {
    if (this.context) {
      this.scheduledTime = this.context.currentTime;
      this.playing = false;
    }
  }

  get isPlaying() {
    if (!this.context) return false;
    return this.scheduledTime > this.context.currentTime;
  }
}

// Global instance
window._pcmPlayerInstance = new PcmPlayer(24000);

// Wrapper functions for Dart JS interop (preserves `this` context)
window.pcmInit = function() {
  try {
    window._pcmPlayerInstance.init();
    return true;
  } catch (e) {
    console.error('pcmInit error:', e);
    return false;
  }
};

window.pcmFeed = function(base64Data) {
  try {
    window._pcmPlayerInstance.feed(base64Data);
  } catch (e) {
    console.error('pcmFeed error:', e);
  }
};

window.pcmStop = function() {
  try {
    window._pcmPlayerInstance.stop();
  } catch (e) {
    console.error('pcmStop error:', e);
  }
};
