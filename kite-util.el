(defun kite--dimmed-face-foreground (face darkness)
  "Return a color value string suitable for passing as the value
  for the :foreground face property that represents a
  'dimmed' (darker) variant of the foreground color of the given
  FACE.  The DARKNESS parameter should be a numeric value in the
  range 0..1; 0 means not to darken the foregroud color, 1 means
  to darken it fully (so that it is the same as the background
  color).  A darkness value of 0.5 would cause a foreground color
  to be returned that is halfway between the foreground and
  background color of FACE.  (If FACE doesn't have a background
  color set, the current frame's background color will be used
  instead.)"
  (flet ((lerp (a b w)
               (+ (* a w)
                  (* b (- 1 w)))))
    (let ((fg (color-name-to-rgb (face-foreground face nil t)))
          (bg (color-name-to-rgb (or (face-background face nil t)
                                     (cdr (assq 'background-color (frame-parameters)))))))
      (color-rgb-to-hex
       (lerp (nth 0 bg) (nth 0 fg) darkness)
       (lerp (nth 1 bg) (nth 1 fg) darkness)
       (lerp (nth 2 bg) (nth 2 fg) darkness)))))

(provide 'kite-util)