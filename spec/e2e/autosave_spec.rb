require 'spec_helper'

describe 'association autosave' do
  module AssociationAutosave
    class Exam; end
    class Lesson; end

    class Student
      include Neo4j::ActiveNode
      property :name
      property :score, type: Integer
      has_many :out, :lessons, model_class: Lesson, autosave: true
    end

    class Lesson
      include Neo4j::ActiveNode
      property :subject
      property :level
      has_many :in, :students, origin: :lessons, autosave: true
      has_many :out, :exams, model_class: Exam, autosave: true
      has_one  :out, :top_student, model_class: Student, autosave: true
    end

    class Exam
      include Neo4j::ActiveNode
      property :name
      property :date, type: Date
      has_many :in, :lessons, model_class: Lesson, autosave: true
    end
  end

  let!(:chris)   { AssociationAutosave::Student.create(name: 'Chris') }
  let!(:math)    { AssociationAutosave::Lesson.create(subject: 'Math', level: 101) }
  let!(:math_midterm) { AssociationAutosave::Exam.create(name: 'Math Midterm' ) }
  let!(:science) { AssociationAutosave::Lesson.create(subject: 'Science', level: 101) }


  before do
    [math, science].each { |lesson| chris.lessons << lesson }   
    math.exams << math_midterm 
  end

  it 'cascades save one level' do
    [math, science].each { |lesson| expect(lesson.level).to eq 101 }
    chris.lessons.each { |lesson| lesson.level = 102 }
    chris.save
    [math, science].each do |lesson|
      lesson.reload
      expect(lesson.level).to eq 102
    end
  end

  it 'cascades across a chain' do
    chris.lessons.each do |lesson|
      lesson.exams.each { |exam| exam.date = Date.today }
    end
    chris.save
    math_midterm.reload
    expect(math_midterm.date).to eq Date.today
  end

  # I don't think this will be supportable
  # has_one associations delegate to 
  it 'saves has_one across one level' do
    math.top_student = chris
    math.top_student.score = 9000
    math.save
    chris.reload
    expect(chris.score).to eq 9000
  end 
end