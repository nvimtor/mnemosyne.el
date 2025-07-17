;;; mnemosyne.el --- Set of utilities for Harvest & org-mode interop -*- lexical-binding: t -*-

;; Copyright (C) 2025  Vitor Leal

;; Author: Vitor Leal <hello@vitorl.com>
;; URL: https://github.com/nvimtor/mnemosyne.el
;; Version: 0.1.0
;; Package-Requires: ((emacs "25.1"))

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Emacs package to auto record, transcribe, and summarize system audio using whisper-cpp & gptel
;;

;;; Code:


(defcustom mnemosyne-audio-save-dir "~/Documents/"
  "Directory to save audio recordings."
  :type 'directory
  :group 'mnemosyne)

(defcustom mnemosyne-models-dir (expand-file-name "~/Projects/mnemosyne/models")
  "Directory where whisper-cpp models are located."
  :type 'directory
  :group 'mnemosyne)

(defcustom mnemosyne-model "ggml-medium.en.bin"
  "Name of whisper-cpp model to use for transcription."
  :type 'string
  :group 'mnemosyne)

(defcustom mnemosyne-audio-microphone "Dipper"
  "Microphone device for audio recordings."
  :type 'string
  :group 'mnemosyne)

(defcustom mnemosyne-whisper-args '()
  "List of arguments for whisper-cpp."
  :type 'alist
  :group 'mnemosyne)

(defun mnemosyne--do-applescript (command)
  "Execute a small AppleScript COMMAND.
Note: all quotes in the COMMAND string will be escaped.
To say something, use:  (do-applescript \"say \\\"Hello\\\"\")"
  (message "%S" command)
  (shell-command
   (format
    "osascript -e \"%s\""
    (replace-regexp-in-string "\"" "\\\\\"" command))))

(defmacro mnemosyne--applescript-generate (as-form)
  (cond ((and (consp as-form) (eq (car as-form) ':tell))
         `(concat "\ntell " ,(cadr as-form)
                  ,@(mapcar (lambda (stmt)
                              `(mnemosyne--applescript-generate ,stmt))
                            (cddr as-form))
                  "\nend tell"))
        ((stringp as-form)
         `(concat "\n" ,as-form))
        ((consp as-form)
         `(concat "\n" ,as-form))
        ((symbolp as-form)
         `(concat "\n" ,as-form))
        (t (error "Invalid form: %S" as-form))))

(defun mnemosyne--create-filename ()
  "Create a filename from the Org outline path and a timestamp."
  (let* ((path (org-get-outline-path t))
         (path-str (string-join path "_"))
         (timestamp (format-time-string "%Y%m%d_%H%M%S")))
    (concat path-str "_" timestamp)))

(defun mnemosyne--start-recording ()
  (interactive)
  (let ((script (mnemosyne--applescript-generate
                 (:tell "application \"QuickTime Player\""
                        "set new_recording to new audio recording"
                        (:tell "new_recording"
                               (format "set microphone to \"%s\"" mnemosyne-audio-microphone))
                        "start new_recording"))))
    (mnemosyne--do-applescript script)))

(defun mnemosyne--transcribe (filepath cb)
  (async-start-process
   "mnemosyne-transcribe"
   "whisper-cli"
   (lambda (result)
      (funcall cb result))
   "-m"
   (concat mnemosyne-models-dir "/" mnemosyne-model)
   "-f"
   filepath
   "-osrt"))

(defun mnemosyne--stop-recording ()
  (interactive)
  (let* ((orig-buf (current-buffer))
         (orig-point (point))
         (filename (mnemosyne--create-filename))
         (filename-wav (concat filename ".wav"))
         (save-path (expand-file-name filename-wav mnemosyne-audio-save-dir))
         (temp-package (expand-file-name "temp.qtpxcomposition" mnemosyne-audio-save-dir))
         (temp-m4a (expand-file-name "temp_audio.m4a" mnemosyne-audio-save-dir))
         (script (mnemosyne--applescript-generate
                  (:tell "application \"QuickTime Player\""
                         "stop document \"Audio Recording\""
                         (format
                          "save document 1 in POSIX file \"%s\""
                          temp-package)
                         "close document 1"))))
    (mnemosyne--do-applescript script)
    (shell-command (format "mv \"%s/Audio Recording.m4a\" \"%s\"" temp-package temp-m4a))
    (shell-command (format "/usr/bin/afconvert -f WAVE -d LEI16 \"%s\" \"%s\"" temp-m4a save-path))
    (shell-command (format "rm \"%s\" && rm -rf \"%s\"" temp-m4a temp-package))
    (mnemosyne--transcribe
     save-path
     (lambda (proc)
       (let ((srt-path (concat save-path ".srt"))
             (gptel-use-context 'system))
         (with-current-buffer orig-buf
           (goto-char orig-point)
           (gptel-request
               nil
             :system (concat
                      "Generate a well-detailed report on this transcript. Identify open questions. Make use of MCP tools if you need, do not ask if you can use them, just use them.\n\n"
                      "Transcript:"
                      "\n```"
                      (with-temp-buffer (insert-file-contents srt-path)
                                        (buffer-string))
                      "\n```")
             :callback (lambda (response info)
                         (when (stringp response)
                           (kill-new response)
                           (message "[mnemosyne] AI summary copied to kill-ring."))))))))))

(defun mnemosyne--org-clock-in-action ()
  (when (org-entry-get nil "MNEMOSYNE" t)
    (mnemosyne--start-recording)))

(defun mnemosyne--org-clock-out-action ()
  (when (org-entry-get nil "MNEMOSYNE" t)
    (mnemosyne--stop-recording)))

(defun mnemosyne--org-clock-out-advice (&rest _args)
  (mnemosyne--org-clock-out-action))

(define-minor-mode mnemosyne-mode
  "Description"
  :init-value nil
  :lighter "Mnemosyne"
  :predicate (org-mode)
  (if mnemosyne-mode
      (progn
        (add-hook 'org-clock-in-hook #'mnemosyne--org-clock-in-action)
        (advice-add 'org-clock-out :before #'mnemosyne--org-clock-out-action-advice))
    (remove-hook 'org-clock-in-hook #'mnemosyne--org-clock-in-action)
    (advice-remove 'org-clock-out #'mnemosyne--org-clock-out-action-advice)))

(provide 'mnemosyne)

;;; mnemosyne.el ends here
