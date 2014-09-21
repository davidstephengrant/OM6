;;===========================================================================;OM API ;Multiplatform API for OpenMusic;Macintosh version (Digitool Macintosh Common Lisp - MCL);;Copyright (C) 2004 IRCAM-Centre Georges Pompidou, Paris, France.; ;This program is free software; you can redistribute it and/or;modify it under the terms of the GNU General Public License;as published by the Free Software Foundation; either version 2;of the License, or (at your option) any later version.;;See file LICENSE for further informations on licensing terms.;;This program is distributed in the hope that it will be useful,;but WITHOUT ANY WARRANTY; without even the implied warranty of;MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the;GNU General Public License for more details.;;You should have received a copy of the GNU General Public License;along with this program; if not, write to the Free Software;Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.;;Authors: Jean Bresson and Augusto Agon;;===========================================================================;;===========================================================================; DocFile; MIDI functions called by OpenMusic; Use MIDISHARE ;;===========================================================================(defpackage :om-midi)(in-package :om-midi)(export '(make-midi-evt          midi-evt-date          midi-evt-type          midi-evt-chan          midi-evt-ref          midi-evt-port          midi-evt-fields          copy-midi-evt          midi-evt-<          )        :om-midi);;; Conventions: channels = 1-16(defstruct midi-evt (date) (type) (chan) (ref) (port) (fields));;; A IS BEFORE B IF...(defun midi-evt-< (a b)  (or (< (midi-evt-date a) (midi-evt-date b)) ;;; A IS BEFORE B      (and (= (midi-evt-date a) (midi-evt-date b)) ;;; A IS = B            (not (find (midi-evt-type a) (list :Note :KeyOn :KeyOff))))  ;;; BUT A IS NOT A NOTE MESSAGE      (and (= (midi-evt-date a) (midi-evt-date b))           (equal (midi-evt-type a) :KeyOff) (equal (midi-evt-type a) :KeyOn))))  ;;; SEND NOTE OFF MESSAGES FIRST; MIDI event type identifiers; = list of supported MIDI events;(export '(Note KeyOn KeyOff KeyPress CtrlChange ProgChange ChanPress PitchBend;               SongPos SongSel Clock Start Continue Stop Tune ActiveSens Reset ;               SysEx Stream Private Process DProcess QFrame Ctrl14b NonRegParam;               RegParam SeqNum Textual Copyright SeqName InstrName Lyric Marker;               CuePoint ChanPrefix EndTrack Tempo SMPTEOffset TimeSign KeySign;               Specific PortPrefix RcvAlarm ApplAlarm Reserved dead);        :om-midi);;; MIDI systems/filesystems must register using pushnew(defvar *midi-systems* nil)(defvar *midi-file-systems* nil);=====================; MIDI FILE API:;=====================;;; THESE FUNCTIONS MUST BE 'DECLARED' BY THE SYSTEM;;; OM CAN CHECK AVAILABILITY BEFORE CALL; args = pathname; returns (values (evtlist nbtracks clicks format))(defmethod load-midi-file-function (midisystem) nil); args = evtlist format clicks; returns pathname(defmethod save-midi-file-function (midisystem) nil);=====================; MIDI PLAYER API:;=====================; args = evt (defmethod send-midi-event-function (midisystem) nil); args = nil(defmethod midi-start-function (midisystem) nil); args = &optional buffersize(defmethod midi-stop-function (midisystem) nil);;; launches a setup process (GUI etc.);;; args = current settings & optional action to perform before any rinitialization;;; returns a formatted list of connections(defmethod midi-setup-function (midisystem &optional action) nil);;; connects ports using the same format of connection list;;; args = formatted conection list(defmethod midi-connect-function (midisystem) nil);;; restart MIDI system(defmethod midi-restart-function (midisystem) nil); args =  port funtion bufsize redirect-to(defmethod midi-in-start-function (midisystem) nil); args = process(defmethod midi-in-stop-function (midisystem) nil)