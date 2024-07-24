import pyaudio
import socket
import threading
import wave

from pathlib import Path

mission_path = None
output_path = Path('C:/Users/raffc/AppData/Local/BeamNG.drive/0.32/art/sounds/')
pacenotes_path = Path('pacenotes')

# Initialize PyAudio
p = pyaudio.PyAudio()

def playWf(wf):
    stream = p.open(format=p.get_format_from_width(wf.getsampwidth()),
                    channels=wf.getnchannels(),
                    rate=wf.getframerate(),
                    output=True)

    # Read and play the WAV file chunk by chunk
    chunk_size = 1024
    data = wf.readframes(chunk_size)
    while data:
        stream.write(data)
        data = wf.readframes(chunk_size)

    # Close the audio stream
    stream.stop_stream()
    stream.close()

    wf.rewind()

# Set the sample rate and audio format
SAMPLE_RATE = 44100
FORMAT = pyaudio.paInt16
CHANNELS = 1

recording = False

i = -1

def record_audio():
    # Open a PyAudio stream for audio recording using the specified input device
    stream = p.open(format=FORMAT, channels=CHANNELS,
                    rate=SAMPLE_RATE, input=True,
                    frames_per_buffer=1024)

    audio_buffer = []

    while recording:
        # Record audio data
        audio_data = stream.read(1024)
        audio_buffer.append(audio_data)

    # once done recording, close the audio stream
    stream.stop_stream()
    stream.close()

    # Create the directories if they don't exist
    full_path = output_path / mission_path / pacenotes_path / f'pacenote_{i}.wav'
    full_path.parent.mkdir(parents=True, exist_ok=True)

    # save the file
    wf = wave.open(str(full_path), 'wb')
    wf.setnchannels(CHANNELS)
    wf.setsampwidth(p.get_sample_size(FORMAT))
    wf.setframerate(SAMPLE_RATE)
    wf.writeframes(b''.join(audio_buffer))
    wf.close()

    # confirm
    audio_thread = threading.Thread(target=playWf, args=(wf_confirm,) )
    audio_thread.daemon = True
    audio_thread.start()

wf_confirm = wave.open('rp_confirm.wav', 'rb')

# Create a socket
server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

# Bind the socket to a specific address and port
server_address = ('127.0.0.1', 43434)
server_socket.bind(server_address)

# Listen for incoming connections
server_socket.listen(1)  # 1 connection at a time

print("Server is listening on {}:{}".format(*server_address))

while True:
    print("Waiting for a connection...")
    client_socket, client_address = server_socket.accept()
    print("Accepted connection from {}:{}".format(*client_address))

    try:
        while True:
            # Receive data from the client
            data = client_socket.recv(1024)
            if not data:
                break  # No more data, the client disconnected
            message = data.decode('utf-8')
            print("Received message:", message)

            # Process the received message (e.g., echo it back to the client)
            response = "Server received: " + message
            # client_socket.sendall(response.encode('utf-8'))

            parts = message.split()
            if parts[0] == 'mission':
                mission_path = Path(parts[1])
            elif parts[0] == 'record_start':
                if mission_path is None:
                    continue

                recording = True
                i += 1
                # spawn a thread for recording
                recording_thread = threading.Thread(target=record_audio)
                recording_thread.daemon = True
                recording_thread.start()

            elif parts[0] == 'record_stop':
                # notify the recording thread to stop
                recording = False

            elif parts[0] == 'mission_end':
                mission_path = None

            elif parts[0] == 'delete_last_pacenote':
                if mission_path is None:
                    continue

                # delete the last pacenote
                full_path = output_path / mission_path / pacenotes_path / f'pacenote_{i}.wav'
                if full_path.exists():
                    full_path.unlink()
                    i -= 1

                # confirm
                audio_thread = threading.Thread(target=playWf, args=(wf_confirm,) )
                audio_thread.daemon = True
                audio_thread.start()

            elif parts[0] == 'set_i':
                print("Setting i")

                # if parts[1] exists, set i to that value
                if len(parts) > 1:
                    # check that it's a valid integer
                    try:
                        i = int(parts[1]) - 1
                    except ValueError:
                        i = -1  # Set a default value
                        print("Invalid value for i. Setting i to 0.")
                else:

                    i = -1

    except Exception as e:
        print("Error:", e)
    finally:
        # Clean up the connection
        client_socket.close()
