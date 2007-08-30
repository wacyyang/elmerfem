
SUBROUTINE ProjectToPlane( Model,Solver,dt,TransientSimulation )
!DEC$ATTRIBUTES DLLEXPORT :: ProjectToPlane
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Convert field computed in cartesian 3D coordinates on a 2D axisymmetric 
!  or cartesian mesh
!
!  ARGUMENTS:
!
!  TYPE(Model_t) :: Model,  
!     INPUT: All model information (mesh, materials, BCs, etc...)
!
!  TYPE(Solver_t) :: Solver
!     INPUT: Linear & nonlinear equation solver options
!
!  REAL(KIND=dp) :: dt,
!     INPUT: Timestep size for time dependent simulations
!
!  LOGICAL :: TransientSimulation
!     INPUT: Steady state or transient simulation
!
!******************************************************************************
  USE DefUtils
  USE GeneralUtils
  USE ElementDescription
  
  IMPLICIT NONE
!------------------------------------------------------------------------------
  TYPE(Solver_t) :: Solver
  TYPE(Model_t) :: Model
  REAL(KIND=dp) :: dt
  LOGICAL :: TransientSimulation
!------------------------------------------------------------------------------
! Local variables
!------------------------------------------------------------------------------

  TYPE(Solver_t), POINTER :: Solver3D
  TYPE(Element_t), POINTER :: Element, FaceElement
  TYPE(Element_t), TARGET  :: TriangleElement
  TYPE(Nodes_t) :: Nodes, FaceNodes, LineNodes
  TYPE(Variable_t), POINTER :: Variable2D, Variable3D
  TYPE(Nodes_t) :: ElementNodes, LineNodes, FaceNodes

  REAL(KIND=dp), POINTER :: Values2D(:), Values3D(:)
  REAL(KIND=dp), POINTER :: Basis(:), dBasisdx(:,:)
  REAL(KIND=dp), POINTER :: PlaneX(:), PlaneY(:), PlaneZ(:)
  REAL(KIND=dp), POINTER :: VolumeX(:), VolumeY(:), VolumeZ(:)
  REAL(KIND=dp) :: CPUTime, at, totcpu
  REAL(KIND=dp) :: x0,y0,z0,xmin,xmax,ymin,ymax,zmin,zmax,r0,rmin,rmax
  REAL(KIND=dp) :: scale, eps, x1,x2,y1,y2,z1,z2,r1,r2
  REAL(KIND=dp) :: xmax3d, xmin3d, ymax3d, ymin3d, zmax3d, zmin3d, rmin3d, rmax3d
  REAL(KIND=dp) :: up,vp,wp,cp,cf,Field1,Field2,Value,MaxRelativeRadius,SqrtElementMetric
  REAL(KIND=dp) :: LocalPoint(3), LocalCoords(3)
  REAL(KIND=dp), POINTER :: MinHeight3D(:), MaxHeight3D(:), MinWidth3D(:), MaxWidth3D(:)
  REAL(KIND=dp), ALLOCATABLE :: IntBasis(:,:), IntExtent(:)

  INTEGER :: MaxInt, Int
  INTEGER, POINTER :: Perm2D(:), Perm3D(:), PlanePerm(:), VolumePerm(:)
  INTEGER :: i,j,k,k2,n,t,node
  INTEGER :: PlaneNodes, VolumeElements, Dofs3D, Dofs2D, corners, face, Intersections
  INTEGER :: Loops(8), inds(3), MinimumHits, AxisHits 
  INTEGER, POINTER :: Order2D(:), Order3D(:)
  INTEGER, ALLOCATABLE :: IntOrder(:), IntNodes(:,:)

  CHARACTER(LEN=MAX_NAME_LEN) :: ConvertFromName, ConvertFromVar, EqName
  LOGICAL :: AllocationsDone = .FALSE., stat, GotIt, Rotate, LimitRadius, Found

!------------------------------------------------------------------------------

  totcpu = CPUTime()
  
  CALL Info( 'ProjectToPlane', ' ' )
  CALL Info( 'ProjectToPlane', '-----------------------------------' )
  CALL Info( 'ProjectToPlane', ' Converting 3D force vectors to 2D ' )
  CALL Info( 'ProjectToPlane', '-----------------------------------' )
  CALL Info( 'ProjectToPlane', ' ' )

  IF ( .TRUE. ) THEN
    IF ( GetLogical( Model % Simulation, 'Output Version Numbers', stat ) ) THEN
      CALL Info( 'ProjectToPlane', 'Version 1.0 by raback (05-02-2007)', LEVEL=4 )
    END IF
    
    ! 3D variables
    !-------------

    ConvertFromName = GetString( Solver % Values, 'Convert From Equation Name', GotIt )
    IF ( .NOT. GotIt )  ConvertFromName = 'induction'
    
    NULLIFY( Solver3D )
    DO i = 1, Model % NumberOfSolvers
      EqName = GetString( Model % Solvers(i) % Values, 'Equation' )
      IF ( TRIM( EqName ) == TRIM( ConvertFromName ) ) THEN
        Solver3D => Model % Solvers(i) 
        EXIT
      END IF
    END DO
    
    IF ( .NOT. ASSOCIATED( Solver3D ) ) THEN
      WRITE( Message, * ) 'Cannot find Solver called ', TRIM( ConvertFromName )
      CALL Error( 'ProjectToPlane', Message )
      CALL Fatal( 'ProjectToPlane','Possibly missing "Convert From Equation Name" field' )
    END IF
    
    ConvertFromVar = GetString( Solver % Values, 'Convert From Variable', GotIt )
    IF ( GotIt ) THEN
      Variable3D => VariableGet( Model % Variables, ConvertFromVar, .TRUE.) 
    ELSE
      Variable3D => Solver3D % Variable 
    END IF

    Values3D => Variable3D % Values
    Perm3D => Variable3D % Perm
    Dofs3D = Variable3D % Dofs
    VolumeElements = Solver3D % NumberOfActiveElements

    VolumeX => Solver3D % Mesh % Nodes % x
    VolumeY => Solver3D % Mesh % Nodes % y      
    VolumeZ => Solver3D % Mesh % Nodes % z      

    VolumePerm => ListGetIntegerArray( Solver % Values,'Volume Permutation',GotIt)
    IF ( gotIt ) THEN
      IF(VolumePerm(1) == 2) VolumeX => Solver3D % Mesh % Nodes % y
      IF(VolumePerm(1) == 3) VolumeX => Solver3D % Mesh % Nodes % z
      IF(VolumePerm(2) == 1) VolumeY => Solver3D % Mesh % Nodes % x
      IF(VolumePerm(2) == 3) VolumeY => Solver3D % Mesh % Nodes % z
      IF(VolumePerm(3) == 1) VolumeZ => Solver3D % Mesh % Nodes % x
      IF(VolumePerm(3) == 2) VolumeZ => Solver3D % Mesh % Nodes % y
    END IF
   
    WRITE( Message, * ) 'Converting from "', TRIM( Variable3D % Name ), &
        '" with ', Dofs3D, 'degrees of freedom'
    CALL Info( 'ProjectToPlane', Message, LEVEL=7 )


    ! 2D variables
    !-------------
    
    PlaneNodes =  Solver % Mesh % NumberOfNodes
    Values2D => Solver % Variable % Values
    Dofs3D = Variable3D % Dofs
    Perm2D => Solver % Variable % Perm

    PlaneX => Solver % Mesh % Nodes % x
    PlaneY => Solver % Mesh % Nodes % y      
    PlaneZ => Solver % Mesh % Nodes % z      

    PlanePerm => ListGetIntegerArray( Solver % Values,'Plane Permutation',GotIt)
    IF ( gotIt ) THEN
      IF(PlanePerm(1) == 2) PlaneX => Solver % Mesh % Nodes % y
      IF(PlanePerm(1) == 3) PlaneX => Solver % Mesh % Nodes % z
      IF(PlanePerm(2) == 1) PlaneY => Solver % Mesh % Nodes % x
      IF(PlanePerm(2) == 3) PlaneY => Solver % Mesh % Nodes % z
      IF(PlanePerm(3) == 1) PlaneZ => Solver % Mesh % Nodes % x
      IF(PlanePerm(3) == 2) PlaneZ => Solver % Mesh % Nodes % y
    END IF

    WRITE( Message, * ) 'Number of 2D mesh nodes: ', Solver % Mesh % NumberOfNodes
    CALL Info( 'ProjectToPlane', Message, LEVEL=16 )
    WRITE( Message, * ) 'Number of 3D mesh nodes: ',Solver3D % Mesh % NumberOfNodes
    CALL Info( 'ProjectToPlane', Message, LEVEL=16 )
!------------------------------------------------------------------------------
!   Allocate stuff
!------------------------------------------------------------------------------

    MaxInt =  PlaneNodes
    ALLOCATE(IntBasis(3,MaxInt), IntNodes(3,MaxInt), IntExtent(MaxInt), IntOrder(MaxInt) )
    ALLOCATE( MinHeight3D(VolumeElements), MaxHeight3D(VolumeElements))
    ALLOCATE( MinWidth3D(VolumeElements), MaxWidth3D(VolumeElements))

    n = Model % MaxElementNodes
    ALLOCATE(ElementNodes % x(n), ElementNodes % y(n), ElementNodes % z(n), Basis(n) )
    ALLOCATE(LineNodes % x(2), LineNodes % y(2), LineNodes % z(2)  )
    ALLOCATE(FaceNodes % x(3), FaceNodes % y(3), FaceNodes % z(3)  )

!   AllocationsDone = .TRUE.

!------------------------------------------------------------------------------
!   Find the scale of the 2D mesh
!------------------------------------------------------------------------------

    xmin = MINVAL( PlaneX )    
    xmax = MAXVAL( PlaneX )
    ymin = MINVAL( PlaneY )    
    ymax = MAXVAL( PlaneY )
    zmin = MINVAL( PlaneZ )    
    zmax = MAXVAL( PlaneZ )

    x0 = xmax - xmin
    y0 = ymax - ymin
    z0 = zmax - zmin

    scale = SQRT(x0*x0 + y0*y0 + z0*z0)    
    LineNodes % y(1) = ymin
    LineNodes % y(2) = LineNodes % y(1) + scale

    Eps = 1.0e-6 * scale    


!------------------------------------------------------------------------------
!  Check control parameters
!------------------------------------------------------------------------------

    Rotate = ListGetLogical(Solver % Values,'Rotate Plane')
    LimitRadius = ListGetLogical(Solver % Values,'Limit Radius',GotIt)
    IF(GotIt) THEN
      MaxRelativeRadius = ListGetConstReal( Solver % Values,'Max Relative Radius',GotIt)
      IF(.NOT. GotIt) MaxRelativeRadius = 0.9999
    END IF

    MinimumHits = ListGetInteger(Solver % Values,'Minimum Hits At Radius',GotIt) 
    IF(.NOT. GotIt) MinimumHits = 1

    AxisHits = ListGetInteger(Solver % Values,'Integration Points At Radius',GotIt) 
    IF(.NOT. GotIt) AxisHits = 2


!------------------------------------------------------------------------------
!   To improve search speed, tabulate values for min and max values of element nodes
!------------------------------------------------------------------------------
   
    DO t = 1, Solver3D % NumberOfActiveElements
      Element => GetActiveElement( t, Solver3D )
      n = GetElementNOFNodes(Element)
      
      ElementNodes % x(1:n) = VolumeX( Element % NodeIndexes(1:n) )
      ElementNodes % y(1:n) = VolumeY( Element % NodeIndexes(1:n) )
      ElementNodes % z(1:n) = VolumeZ( Element % NodeIndexes(1:n) )
      
      MinHeight3D(t) = MINVAL(ElementNodes % z(1:n))
      MaxHeight3D(t) = MAXVAL(ElementNodes % z(1:n))
      
      IF(Rotate) THEN
        MinWidth3D(t) = SQRT( MINVAL(ElementNodes % x(1:n)**2 + ElementNodes % y(1:n)**2) )
        MaxWidth3D(t) = SQRT( MAXVAL(ElementNodes % x(1:n)**2 + ElementNodes % y(1:n)**2) )
      ELSE
        MinWidth3D(t) = MINVAL(ElementNodes % x(1:n))
        MaxWidth3D(t) = MAXVAL(ElementNodes % x(1:n))                  
      END  IF
    END DO
    rmax3d = MAXVAL(MaxWidth3D)
 
  END IF
  

  ! By contruction split everything into triangles        
  corners = 3
  TriangleElement % TYPE => GetElementType( 303, .FALSE. )
  FaceElement => TriangleElement
  Loops = 0

  !   Loop over 2D nodes:
  !   -------------------
  DO node = 1, PlaneNodes

    Loops(1) = Loops(1) + 1

    at = CPUTime()
 
    IF(Perm2D(node) == 0) CYCLE

    x0 = PlaneX(node)
    y0 = PlaneY(node)
    z0 = PlaneZ(node)

    IF(LimitRadius) THEN
      x0 = MIN( x0, MaxRelativeRadius * rmax3d )
    END IF
    LineNodes % x(1) = x0
    LineNodes % x(2) = x0
    LineNodes % z(1) = z0
    LineNodes % z(2) = z0

    
    !   Loop over 3D elements:
    !   -------------------
    Int = 0
    DO t = 1, VolumeElements
      
      Loops(2) = Loops(2) + 1

      IF(z0 > MaxHeight3D(t) + Eps) CYCLE
      IF(z0 < MinHeight3D(t) - Eps) CYCLE

      IF(x0 > MaxWidth3D(t) + Eps) CYCLE
      IF(x0 < MinWidth3D(t) - Eps) CYCLE

      Loops(3) = Loops(3) + 1

!------------------------------------------------------------------------------
      Element => GetActiveElement( t, Solver3D )
      n = GetElementNOFNodes(Element)
      ElementNodes % x(1:n) = VolumeX( Element % NodeIndexes(1:n) )
      ElementNodes % y(1:n) = VolumeY( Element % NodeIndexes(1:n) )
      ElementNodes % z(1:n) = VolumeZ( Element % NodeIndexes(1:n) )
!------------------------------------------------------------------------------

      Intersections = 0
      DO face=1, 12

        CALL GetLinearTriangleFaces( Element, face, inds, GotIt )
        IF(.NOT. GotIt) EXIT

        Loops(4) = Loops(4) + 1               

        IF(.NOT. Rotate ) THEN
          FaceNodes % x(1:corners) = ElementNodes % x(inds(1:corners))
          FaceNodes % y(1:corners) = ElementNodes % y(inds(1:corners))
          FaceNodes % z(1:corners) = ElementNodes % z(inds(1:corners))
        ELSE
          FaceNodes % x(1:corners) = SQRT( &
              ElementNodes % x(inds(1:corners))**2.0d0 + &
              ElementNodes % y(inds(1:corners)) **2.0d0 )                       
          FaceNodes % y(1:corners) = 0.0d0            
          FaceNodes % z(1:corners) = ElementNodes % z(inds(1:corners))                       
        END IF
          
        xmin = MINVAL( FaceNodes % x(1:n) )
        xmax = MAXVAL( FaceNodes % x(1:n) )                  
        IF( x0 < xmin - Eps) CYCLE
        IF( x0 > xmax + Eps) CYCLE
        
        zmin = MINVAL( FaceNodes % z(1:n) )
        zmax = MAXVAL( FaceNodes % z(1:n) )                     
        IF( z0 < zmin - Eps) CYCLE
        IF( z0 > zmax + Eps) CYCLE

        CALL LineFaceIntersect(Element,FaceNodes,corners,LineNodes,Found,up,vp,cp)
        IF(.NOT. Found) CYCLE

        Loops(5) = Loops(5) + 1

        Intersections = Intersections + 1
        Int = Int + 1
        IF(Int > MaxInt) CALL AllocateMoreSpace()

        CALL NodalBasisFunctions(Corners, Basis, FaceElement, up, vp, 0.0d0)

        IF(Rotate) THEN
          x1 = SUM(Basis(1:corners) * ElementNodes % x(inds(1:corners)))
          y1 = SUM(Basis(1:corners) * ElementNodes % y(inds(1:corners)))
          cp = ATAN2(x1, y1)
        END IF

        IntExtent(Int) = cp
        IntBasis(1:corners,Int) = Basis(1:corners)
        IntNodes(1:corners,Int) = Element % NodeIndexes( inds(1:corners) ) 
      END DO

      IF( Intersections /= 0 .AND. Intersections /= 2 ) THEN
        Loops(6) = Loops(6) + 1
      END IF
      
    END DO


    IF(Int > MinimumHits) THEN
      
      Loops(7) = Loops(7) + 1
      
      DO i=1,Int 
        IntOrder(i) = i
      END DO
      
      CALL SortR( Int, IntOrder, IntExtent)
      
      Value = 0.0d0
      IF(Int > 1) THEN
        Value = 0.0d0
        DO j=1,Int-1
          k = IntOrder(j)
          k2 = IntOrder(j+1)
          Field1 = SUM( IntBasis(:,k) * Values3D( Perm3D(IntNodes(:,k))) )      
          Field2 = SUM( IntBasis(:,k2) * Values3D( Perm3D(IntNodes(:,k2))) )
          Value = Value + 0.5d0 * (Field1 + Field2) * (IntExtent(j) - IntExtent(j+1))
        END DO
        
        IF(Rotate) THEN
          cf = 2*PI -  (IntExtent(1) - IntExtent(Int))
          k = IntOrder(Int)
          k2 = IntOrder(1)      
          Field1 = SUM( IntBasis(:,k) * Values3D( Perm3D(IntNodes(:,k))) )      
          Field2 = SUM( IntBasis(:,k2) * Values3D( Perm3D(IntNodes(:,k2))) )
          Value = Value + 0.5d0 * (Field1 + Field2) * cf
          Value = Value / (2.0*PI)
        ELSE
          Value = Value / (IntExtent(1)-IntExtent(Int)) 
        END IF
      ELSE
        Value = SUM( IntBasis(:,k) * Values3D( Perm3D(IntNodes(:,1))) )            
      END IF

    ELSE
      
      LocalPoint(1) = x0
      LocalPoint(2) = y0
      LocalPoint(3) = z0
      GotIt = .FALSE.
      
      ! Take symmetric hits if not exactly on the axis
      IF( Rotate .AND. ABS(x0) > Eps) THEN
        Loops(8) = Loops(8) + 1
        k2 = AxisHits
      ELSE
        k2 = 1
      END IF
      
      j = 0
      Value = 0.0d0

      DO k=1,k2
        GotIt = .FALSE.

        IF(k > 1) THEN
          LocalPoint(1) = COS( 2*PI*(k-1.0d0)/AxisHits )
          LocalPoint(2) = SIN( 2*PI*(k-1.0d0)/AxisHits )
        END IF

        DO t = 1, VolumeElements

          IF(z0 > MaxHeight3D(t) + Eps) CYCLE
          IF(z0 < MinHeight3D(t) - Eps) CYCLE

          Element => GetActiveElement( t, Solver3D )
          n = GetElementNOFNodes(Element)

          ElementNodes % x(1:n) = VolumeX( Element % NodeIndexes(1:n) )
          IF( MINVAL(ElementNodes % x(1:n)) > x0 ) CYCLE
          IF( MAXVAL(ElementNodes % x(1:n)) < x0 ) CYCLE

          ElementNodes % y(1:n) = VolumeY( Element % NodeIndexes(1:n) )
          IF( MINVAL(ElementNodes % y(1:n)) > y0 ) CYCLE
          IF( MAXVAL(ElementNodes % y(1:n)) < y0 ) CYCLE

          ElementNodes % z(1:n) = VolumeZ( Element % NodeIndexes(1:n) )
        
          IF ( PointInElement( Element, ElementNodes, LocalPoint, LocalCoords ) ) THEN
            GotIt = .TRUE.
            EXIT
          END IF
        END DO
        
        IF(GotIt) THEN
          j = j + 1
          up = LocalCoords(1)
          vp = LocalCoords(2)
          wp = LocalCoords(3)
          
          stat = ElementInfo( Element,ElementNodes,up,vp,wp,SqrtElementMetric,Basis)
          
          Field1 = SUM( Basis(1:n) * Values3D( Perm3D(Element % NodeIndexes(1:n))) )      
          Value = Value + Field1
        END IF
      END DO

      IF( j > 0 ) THEN
        Value = Value / j
      ELSE
        Value = 0
        PRINT *,'No hits for this node',node,x0,y0,z0
      END IF

    END IF

    IF (ASSOCIATED(Perm2D)) THEN
      Values2D(Perm2D(node)) = Value
    ELSE
      Values2D(node) = Value
    END IF
  END DO

  Solver % Variable % Norm = SQRT( SUM(Values2D**2) / SIZE(Perm2D) )
  

  WRITE( Message, * ) 'Basic search loops: ',Loops(2:5)
  CALL Info( 'ProjectToPlane', Message, LEVEL=4 )

  IF(Loops(5) > 0) THEN    
    WRITE( Message, * ) 'Special cases loops: ',Loops(6:8)
    CALL Info( 'ProjectToPlane', Message, LEVEL=4 )
  END IF

  WRITE( Message, * ) 'Total CPU time used: ', CPUTime() - totcpu
  CALL INFO( 'ProjectToPlane', Message, LEVEL=8 )
  CALL Info( 'ProjectToPlane', ' ' )
  CALL Info( 'ProjectToPlane', 'All done' )
  CALL Info( 'ProjectToPlane', ' ' )

  DEALLOCATE(IntBasis, IntNodes, IntExtent, IntOrder, &
      MinHeight3D, MaxHeight3D, MinWidth3D, MaxWidth3D)


CONTAINS
  

  SUBROUTINE AllocateMoreSpace()
   
    REAL(KIND=dp), ALLOCATABLE :: TmpBasis(:,:), TmpExtent(:)
    INTEGER, ALLOCATABLE :: TmpOrder(:), TmpNodes(:,:)
    INTEGER :: OldMaxInt
    
    OldMaxInt = MaxInt
    
    ALLOCATE(TmpBasis(3,MaxInt), TmpNodes(3,MaxInt), TmpExtent(MaxInt), TmpOrder(MaxInt) )
    
    TmpBasis(:,1:OldMaxInt) = IntBasis(:,1:OldMaxInt)
    TmpNodes(:,1:OldMaxInt) = IntNodes(:,1:OldMaxInt) 
    TmpExtent(1:OldMaxInt) = IntExtent(1:OldMaxInt)
    TmpOrder(1:OldMaxInt) = IntOrder(1:OldMaxInt)
    
    MaxInt = MaxInt + PlaneNodes
    DEALLOCATE(IntBasis, IntNodes, IntExtent, IntOrder)
    ALLOCATE(IntBasis(3,MaxInt), IntNodes(3,MaxInt), IntExtent(MaxInt), IntOrder(MaxInt) )
    
    IntBasis(:,1:OldMaxInt) = TmpBasis(:,1:OldMaxInt)
    IntNodes(:,1:OldMaxInt) = TmpNodes(:,1:OldMaxInt) 
    IntExtent(1:OldMaxInt) = TmpExtent(1:OldMaxInt)
    IntOrder(1:OldMaxInt) = TmpOrder(1:OldMaxInt)
    
    DEALLOCATE(TmpBasis, TmpNodes, TmpExtent, TmpOrder)
    ! PRINT *,'Allocated more space',MaxInt
    
  END SUBROUTINE AllocateMoreSpace


!------------------------------------------------------------------------------
! 3D mesh faces.
!------------------------------------------------------------------------------
  SUBROUTINE GetLinearTriangleFaces( Element, face, inds, GotIt )
    IMPLICIT NONE
!------------------------------------------------------------------------------
    TYPE(Element_t), POINTER :: Element
    INTEGER :: face, inds(:)
    LOGICAL :: GotIt
!------------------------------------------------------------------------------
    LOGICAL :: Visited
    INTEGER :: faces, elemfamily     
    INTEGER, POINTER :: FaceMap(:,:)
    INTEGER, TARGET  :: TetraFaceMap(4,3), BrickFaceMap(12,3), WedgeFaceMap(8,3), PyramidFaceMap(6,3)    

    SAVE Visited, TetraFaceMap, BrickFaceMap, WedgeFaceMap, PyramidFaceMap, FaceMap, faces

!------------------------------------------------------------------------------

    IF(.NOT. Visited ) THEN  
      TetraFaceMap(1,:) = (/ 1, 2, 3 /)
      TetraFaceMap(2,:) = (/ 1, 2, 4 /)
      TetraFaceMap(3,:) = (/ 2, 3, 4 /)
      TetraFaceMap(4,:) = (/ 3, 1, 4 /)
      
      WedgeFaceMap(1,:) = (/ 1, 2, 3 /)
      WedgeFaceMap(2,:) = (/ 4, 5, 6 /)
      WedgeFaceMap(3,:) = (/ 1, 2, 5 /)
      WedgeFaceMap(4,:) = (/ 5, 4, 1 /)
      WedgeFaceMap(5,:) = (/ 3, 2, 5 /)
      WedgeFaceMap(6,:) = (/ 5, 6, 3/)
      WedgeFaceMap(7,:) = (/ 3, 1, 4 /)
      WedgeFaceMap(8,:) = (/ 4, 6, 3/)
      
      PyramidFaceMap(1,:) = (/ 1, 2, 3 /)
      PyramidFaceMap(2,:) = (/ 3, 4, 1 /)
      PyramidFaceMap(3,:) = (/ 1, 2, 5 /)
      PyramidFaceMap(4,:) = (/ 2, 3, 5 /)
      PyramidFaceMap(5,:) = (/ 3, 4, 5 /)
      PyramidFaceMap(6,:) = (/ 4, 1, 5 /)
      
      BrickFaceMap(1,:) = (/ 1, 2, 3 /)
      BrickFaceMap(2,:) = (/ 3, 4, 1 /)
      BrickFaceMap(3,:) = (/ 5, 6, 7 /)
      BrickFaceMap(4,:) = (/ 7, 8, 5 /)      
      BrickFaceMap(5,:) = (/ 1, 2, 6 /)
      BrickFaceMap(6,:) = (/ 6, 5, 1 /)      
      BrickFaceMap(7,:) = (/ 2, 3, 7 /)
      BrickFaceMap(8,:) = (/ 7, 6, 2 /)      
      BrickFaceMap(9,:) = (/ 3, 4, 8 /)
      BrickFaceMap(10,:) = (/ 8, 7, 3 /)      
      BrickFaceMap(11,:) = (/ 4, 1, 5 /)
      BrickFaceMap(12,:) = (/ 5, 8, 4 /)

      Visited = .TRUE.
    END IF


    IF(face == 1) THEN
      elemfamily = Element % TYPE % ElementCode / 100
      SELECT CASE( elemfamily )
      CASE(5)
        faces = 4
        FaceMap => TetraFaceMap
      CASE(6)
        faces = 6
        FaceMap => PyramidFaceMap
      CASE(7)
        faces = 8 
        FaceMap => WedgeFaceMap
      CASE(8)
        faces = 12
        FaceMap => BrickFaceMap
      CASE DEFAULT
        WRITE(Message,*) 'Element type',Element % TYPE % ElementCode,'not implemented.' 
        CALL Fatal('FindMeshFaces',Message)
      END SELECT
    END IF
    

    IF(face > faces) THEN
      GotIt = .FALSE.
    ELSE
      GotIt = .TRUE.
      Inds(1:3) = FaceMap(face,1:3) 
    END IF
  

!------------------------------------------------------------------------------
  END SUBROUTINE GetLinearTriangleFaces
!------------------------------------------------------------------------------


  SUBROUTINE LineFaceIntersect(Element,Plane,dim,Line,Inside,up,vp,cp)
!---------------------------------------------------------------------------
! This subroutine tests whether the line segment goes through the current
! face of the element. If true the weights and index to the closest node 
! are returned. 
!---------------------------------------------------------------------------

    TYPE(Nodes_t) :: Plane, Line
    TYPE(Element_t), POINTER   :: Element
    INTEGER :: dim,n
    LOGICAL :: Inside
    REAL (KIND=dp) :: up,vp,cp

    REAL (KIND=dp) :: A(3,3),A0(3,3),B(3),C(3),Eps,Eps2,detA,absA,ds
    LOGICAL :: FiniteLine = .FALSE.

    Inside = .FALSE.

    Eps = 1.0d-8
    Eps2 = SQRT(TINY(Eps2))    

    ! In 2D the intersection is between two lines
    IF(DIM == 2) THEN
      A(1,1) = Line % x(2) - Line % x(1)
      A(2,1) = Line % y(2) - Line % y(1)
      A(1,2) = Plane % x(1) - Plane % x(2)
      A(2,2) = Plane % y(1) - Plane % y(2)
      A0 = A

      detA = A(1,1)*A(2,2)-A(1,2)*A(2,1)
      absA = SUM(ABS(A(1,1:2))) * SUM(ABS(A(2,1:2)))

      ! Lines are almost parallel => no intersection possible
      IF(ABS(detA) <= eps * absA + Eps2) RETURN

      B(1) = Plane % x(1) - Line % x(1) 
      B(2) = Plane % y(1) - Line % y(1) 

      CALL InvertMatrix( A,2 )
      C(1:2) = MATMUL(A(1:2,1:2),B(1:2))
     
      IF(FiniteLine .AND. ( C(1) < -Eps .OR. C(2) > 1.0d0 + Eps) ) RETURN
      IF(C(2) < -Eps .OR. C(2) > 1.0d0 + Eps) RETURN

      Inside = .TRUE.

      ! Relate the point of intersection to local coordinates
      up = -1.0d0 + 2.0d0 * C(2)
      ! Extent of the line segment 
      cp = c(1)      

    ELSE IF(DIM == 3) THEN
      A(1,1) = Line % x(2) - Line % x(1)
      A(2,1) = Line % y(2) - Line % y(1)
      A(3,1) = Line % z(2) - Line % z(1)

      A(1,2) = Plane % x(1) - Plane % x(2)
      A(2,2) = Plane % y(1) - Plane % y(2)
      A(3,2) = Plane % z(1) - Plane % z(2)
      
      A(1,3) = Plane % x(1) - Plane % x(3)
      A(2,3) = Plane % y(1) - Plane % y(3)
      A(3,3) = Plane % z(1) - Plane % z(3)
      
      ! Check for linearly dependent vectors
      detA = A(1,1)*(A(2,2)*A(3,3)-A(2,3)*A(3,2)) &
          - A(1,2)*(A(2,1)*A(3,3)-A(2,3)*A(3,1)) &
          + A(1,3)*(A(2,1)*A(3,2)-A(2,2)*A(3,1))
      absA = SUM(ABS(A(1,1:3))) * SUM(ABS(A(2,1:3))) * SUM(ABS(A(3,1:3))) 
      
      IF(ABS(detA) <= eps * absA + Eps2) RETURN

      B(1) = Plane % x(1) - Line % x(1)
      B(2) = Plane % y(1) - Line % y(1)
      B(3) = Plane % z(1) - Line % z(1)

      CALL InvertMatrix( A,3 )

      C(1:3) = MATMUL( A(1:3,1:3),B(1:3) )

      IF( FiniteLine .AND. ( C(1) < 0.0 .OR. C(1) > 1.0d0 ) ) RETURN
      
      IF( ANY(C(2:3) < -Eps) .OR. ANY(C(2:3) > 1.0d0 + Eps) ) RETURN
      IF(C(2)+C(3) > 1.0d0 + Eps) RETURN
      
      Inside = .TRUE. 

      ! Relate the point of intersection to local coordinates
      up = C(2)
      vp = C(3)
      
      ! Extent of the line segment 
      cp = c(1)      
    END IF

  END SUBROUTINE LineFaceIntersect
  
!------------------------------------------------------------------------------
END SUBROUTINE ProjectToPlane
!------------------------------------------------------------------------------


