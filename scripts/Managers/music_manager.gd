extends AudioStreamPlayer2D

func play_song(path: String):
	var song: AudioStream = ResourceLoader.load(path)
	stream = song
	playing = true
