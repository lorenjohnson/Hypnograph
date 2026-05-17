# Current

Live working notes for the current branch/session. Keep raw observations here until they are sorted into immediate fixes, active projects, backlog, or discard.

- There is an issue that I found in this testing, which is when I open a current hypnograph that already exists and then make some changes. images, we try and render it and then I quit. it doesn't actually prompt me to save it, nor does it retain the changes I made which surprises me we do already have guards on that in one or two places, I think. so maybe one is missing here. Otherwise, Otherwise, I think that Hypnograph opens the last opened file by default, and that that should be a setting with the default of on and it should be in the settings menu which is open last opened hypnograph or whatever yeah so it's two different things yeah. to say is if it can't find the previously ump and hypnograph or there wasn't one, and then that's when it uses the default session. Yeah. Or obviously if the setting is turned off to use the last... opened Hypnograph, then it just opens the default session then as well. unless of course somebody explicitly opened a hypnogram file in which case that's what gets opened. Perhaps we can for now just address the guard on close for unsaved changes.
- Test slow loading apple photos resources. Needs debug scenario to show "waiting" state.
- Failure and timeout debug modes show an issue...
- Make "clear sequence" / restart 1st class? No probably remove that option from settings entirely and just make more clear this is New. BUT when making a new Hypnogram it didn't ask me to save?
- It is already a priority project to make it possible to start with a blank composition, but I think this should be the default and the blank screen becomes an ideal home for a first step in guiding the user on first entry.
- Effect chain editing is really cumbersome on a 13" screen. They go over the playbar. Maybe some minimal Effects Composer mode built into play?
- Auto Generate and no Looping on by default, but since these go together is it too complex as it is to get back to default Hypnograph / watch my life mode? 
- Should we start paused by default or play by default?
- Do we save the current composition and playhead position?
- Is there a playhead in the sequence area too?
- Is there a playhead for full clip trim mode? yes i think so
- Do we have a timecode/timeline scal underneath the playhead above the layer timelimes?
- Do we represent transitions as an overlay on timelimes?
- How do time-based effects work with the playhead? Try it
- Bug: Finder action "Add to Hypnograph Source" is not installing - Automator action fails. Also, try adding a sourceFolder without any files in it--it may cause a crash?
