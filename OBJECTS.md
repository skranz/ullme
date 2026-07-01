# uLLMe Objects

Example for objects used by uLLme are slides, ps [problem sets], or lectures. Basic definitions are in inst/objects.

Objects can be bound to AI Tutor instances and supplied to Skills as structured
course context.

## REQUIRED FIELDS OF AN OBJECT

oid: object id that will be used in files and place holders to reference to an object

name: a longer name of the object possibly used in some texts.

level: (course) 
  - course means we can have multiple instances of the object per course. A course always means a unique combination of course and semester.

type: (doc|event)
  - doc is used for documents like slides, or lectures. Each instance has at least one file stored in the materials directory. We can have multiple files in different formats for a document, like slides1.pdf and slides1.tex. There can also be extra materials for each object file to an instance like multiple images. They should be stored in a subdirectory postfix '_extra' like "slides1_extra"
  
descr:
  - A verbal description of the object. Can help an AI or human user to understand it.
  
## OPTIONAL FIELDS OF AN OBJECT

doc_dir: 
  Preferred subdirectory of materials where the files of a document shall be stored.

linked_to:
  Example in ps_sol we have 'linked_to: ps' This means each ps_sol object instance is linked to a ps instance.

progresses:
  For event objects. They can progress object instances. E.g. for lecture we have  'progresses: [slides, script]' this means a lecture can progress slides or a script.
  
# Specifying object instances

Object type files under `inst/objects` describe what an object means. A
course-specific object index describes which actual course materials or events
are instances of that type.

New indexes use the canonical path:

```text
<course>/objects/<oid>.yaml
```

For compatibility, uLLMe can still read legacy `{oid}_inst.yaml` and
`{oid}_inst.yml` files from the course root. New writes always use the
canonical path.


## Object instances for doc objects 

How does an instance file for a doc object look like? Let us take ps_sol_inst.yml as example:

```yaml
oid: ps_sol
objects:
  - id: ps1_sol
    order: 1
    files:
      - path: ps/ps1_sol.tex
        format: tex
      - path: ps/ps1_sol.pdf
        format: pdf
    linked_to: ps1
    extra_files: [ps/ps1_figure1.png]

  - id: ps2a_sol
    order: 2
    files: [ps/ps2a_sol.tex, ps/ps2a_sol.pdf]
    linked_to: ps2a
    extra_files: []
```

We don't specify the file directories but expect them in the doc_dir specified by the object. If the files are in some other directory we want to copy them.

`id` is the stable ID of the object instance. Legacy `docid` and `eventid`
fields remain readable. Because `ps_sol` declares `linked_to: ps`, values such
as `ps1` and `ps2a` must exist in the course's `ps` index.

Note that instance files should ideally sort the object instances in the correct order, i.e. problem sets in the sequence they are used in the course. An LLM should be hopefully be able to do it.

## Object instances for event objects 

Here an example for an instance file of the lecture object in a course, an event object.

```yaml
oid: lecture
objects:
  - id: lecture_1
    order: 1
    date: "2025-11-01"
    start_time: "10:15"
    end_time: "11:45"
    progress:
      slides:
        id: [slides1a]
        descr: |
          Began course and finished the Cournot Model on the slides.
        
  - id: lecture_2
    order: 2
    date: "2025-11-04"
    start_time: "10:15"
    end_time: "11:45"
    progress:
      slides:
        id: [slides1a, slides1b]
        descr: |
          Finished slides 1a and also taught first 5 slides of 1b.
```

These instance files can help AI Tutors bind the correct material and help
Skills generate outputs such as summaries or quizzes.

# Uses of objects

Objects are mainly used by AI Tutors and Skills.

## Using objects as placeholders in prompts and other texts

There we would typically upload a text representation and possibly figures in the additiona material of the relevant object instance. We should specify some default ranking of file formats, like md before tex, before html, before image version of pdf.


