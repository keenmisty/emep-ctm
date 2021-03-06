! <PhyChem_ml.f90 - A component of the EMEP MSC-W Chemical transport Model, version rv4_10(3282)>
!*****************************************************************************!
!*
!*  Copyright (C) 2007-2016 met.no
!*
!*  Contact information:
!*  Norwegian Meteorological Institute
!*  Box 43 Blindern
!*  0313 OSLO
!*  NORWAY
!*  email: emep.mscw@met.no
!*  http://www.emep.int
!*
!*    This program is free software: you can redistribute it and/or modify
!*    it under the terms of the GNU General Public License as published by
!*    the Free Software Foundation, either version 3 of the License, or
!*    (at your option) any later version.
!*
!*    This program is distributed in the hope that it will be useful,
!*    but WITHOUT ANY WARRANTY; without even the implied warranty of
!*    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!*    GNU General Public License for more details.
!*
!*    You should have received a copy of the GNU General Public License
!*    along with this program.  If not, see <http://www.gnu.org/licenses/>.
!*****************************************************************************!
module PhyChem_ml
!
!     physical and chemical routine calls within one advection step
!     driven from here
!
!     Output of hourly data
!
!-----------------------------------------------------------------------------
use Advection_ml,     only: advecdiff_poles,advecdiff_Eta!,adv_int
use Biogenics_ml,     only: Set_SoilNOx
use CheckStop_ml,     only: CheckStop
use Chemfields_ml,    only: xn_adv,cfac,xn_shl
use ChemSpecs,        only: IXADV_SO2, IXADV_NH3, IXADV_O3, NSPEC_SHL, species
use CoDep_ml,         only: make_so2nh3_24hr
use DA_ml,            only: DEBUG_DA_1STEP
use DA_3DVar_ml,      only: main_3dvar, T_3DVAR
use Derived_ml,       only: DerivedProds, Derived, num_deriv2d
use DerivedFields_ml, only: d_2d, f_2d
use DryDep_ml,        only: init_drydep
use EmisDef_ml,       only: loc_frac
use Emissions_ml,     only: EmisSet,uemep_emis
!use Gravset_ml,       only: gravset
use GridValues_ml,    only: debug_proc,debug_li,debug_lj,&
                            glon,glat,projection,i_local,j_local,i_fdom,j_fdom
use ModelConstants_ml,only: MasterProc, KMAX_MID, nmax, nstep &
                           ,dt_advec       & ! time-step for phyche/advection
                           ,DEBUG, PPBINV, PPTINV  & 
                           ,END_OF_EMEPDAY & ! (usually 6am)
                           ,IOU_INST       &
                           ,FORECAST       & ! use advecdiff_poles on FORECAST mode
                           ,ANALYSIS       & ! 3D-VAR Analysis
                           ,SOURCE_RECEPTOR&
!                          ,USE_GRAVSET&
                           ,FREQ_HOURLY    & ! hourly netcdf output frequency
                           ,USE_POLLEN, USE_EtaCOORDINATES,JUMPOVER29FEB&
                           ,USE_uEMEP, IOU_HOUR, IOU_HOUR_INST
use MetFields_ml,     only: ps,roa,z_bnd,z_mid,cc3dmax, &
                            zen,coszen,Idirect,Idiffuse
use OutputChem_ml,    only: WrtChem
use My_Outputs_ml ,   only: NHOURLY_OUT, FREQ_SITE, FREQ_SONDE
use My_Timing_ml,     only: Code_timer, Add_2timing, tim_before, tim_after
use Nest_ml,          only: readxn, wrtxn
use Par_ml,           only: me, LIMAX, LJMAX
use Pollen_ml,        only: pollen_dump,pollen_read
use SoilWater_ml,     only: Set_SoilWater
use TimeDate_ml,      only: date,daynumber,day_of_year, add_secs, &
                            current_date, timestamp,  &
                            make_timestamp, make_current_date
use TimeDate_ExtraUtil_ml,only : date2string
use Trajectory_ml,    only: trajectory_out     ! 'Aircraft'-type  outputs
use Radiation_ml,     only: SolarSetup,       &! sets up radn params
                            ZenithAngle,      &! gets zenith angle
                            ClearSkyRadn,     &! Idirect, Idiffuse
                            CloudAtten         !
use Runchem_ml,       only: runchem   ! Calls setup subs and runs chemistry
use Sites_ml,         only: siteswrt_surf, siteswrt_sondes    ! outputs
use Timefactors_ml,   only: NewDayFactors
!-----------------------------------------------------------------------------
implicit none
private

public  :: phyche
private :: debug_concs

contains
!++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
subroutine phyche()

  logical, save :: End_of_Day = .false.
  integer :: ndays,status
  real :: thour
  type(timestamp) :: ts_now !date in timestamp format
  logical,save :: first_call = .true.

  !------------------------------------------------------------------
  !     physical and  chemical routines.


  !     Hours since midnight at any time-step
  !    using current_date we have already nstep taken into account
  thour = real(current_date%hour) + current_date%seconds/3600.0

  if(DEBUG%PHYCHEM.and.debug_proc ) then
    if(first_call)  write(*, *) "PhyChe First", me, debug_proc
    call debug_concs("PhyChe start ")

    if(current_date%hour==12) then
      ndays = day_of_year(current_date%year,current_date%month, &
           current_date%day)
      write(*,*) 'thour,ndays,nstep,dt', thour,ndays,nstep,dt_advec
    endif
  endif

! if(MasterProc) write(*,"(a15,i6,f8.3)") 'timestep nr.',nstep,thour

  call Code_timer(tim_before)
  call readxn(current_date) !Read xn_adv from earlier runs
  if(FORECAST.and.USE_POLLEN) call pollen_read ()
  call Add_2timing(19,tim_after,tim_before,"nest: Read")
  if(ANALYSIS.and.first_call)then
    call main_3dvar(status)   ! 3D-VAR Analysis for "Zero hour"
    call CheckStop(status,"main_3dvar in PhyChem_ml/PhyChe")
    call Add_2timing(T_3DVAR,tim_after,tim_before)
    if(DEBUG_DA_1STEP)then
      if(MasterProc)&
        write(*,*) 'ANALYSIS DEBUG_DA_1STEP: only 1st assimilation step'
      call Derived(dt_advec,End_of_Day)
      return
    endif
  endif
  if(FORECAST.and.first_call)then     ! Zero hour output
    call Derived(dt_advec,End_of_Day,ONLY_IOU=IOU_HOUR) ! update D2D outputs, to avoid
    call WrtChem(ONLY_HOUR=IOU_HOUR)    ! eg PM10:=0.0 on first output
    call Add_2timing(35,tim_after,tim_before,"phyche:outs")
  endif

  call EmisSet(current_date)
  call Add_2timing(15,tim_after,tim_before,"phyche:EmisSet")

  !       For safety we initialise instant. values here to zero.
  !       Usually not needed, but sometimes
  !       ==================
  d_2d(:,:,:,IOU_INST) = 0.0
  !       ==================


  !===================================

  call SolarSetup(current_date%year,current_date%month,current_date%day,thour)

  call ZenithAngle(thour, glat, glon, zen, coszen )

  if(DEBUG%PHYCHEM.and.debug_proc)&
    write(*,*) "PhyChem ZenRad ", current_date%day, current_date%hour, &
        thour, glon(debug_li,debug_lj),glat(debug_li,debug_lj), &
        zen(debug_li,debug_lj),coszen(debug_li,debug_lj)

  call ClearSkyRadn(ps(:,:,1),coszen,Idirect,Idiffuse)

  call CloudAtten(cc3dmax(:,:,KMAX_MID),Idirect,Idiffuse)

  !===================================
  call Add_2timing(16,tim_after,tim_before,"phyche:ZenAng")

  !================
  ! advecdiff_poles considers the local Courant number along a 1D line
  ! and divides the advection step "locally" in a number of substeps.
  ! Up north in a LatLong domain such as MACC02, mapfactors go up to four,
  ! so using advecdiff_poles pays off, even though none of the poles are
  ! included in the domain.
  ! For efficient parallellisation each subdomain needs to have the same work 
  ! load; this can be obtained by setting NPROCY=1 (number of subdomains in 
  ! latitude- or y-direction).
  ! Then, all subdomains have exactly the same geometry.

  if(USE_EtaCOORDINATES)then
    call advecdiff_Eta
  else
    call advecdiff_poles
  endif

! if(USE_GRAVSET) call gravset

  call Add_2timing(17,tim_after,tim_before,"phyche:advecdiff")
  !================

  call Code_timer(tim_before)

  !/ See if we are calculating any before-after chemistry productions:

  !=============================
  if ( nstep == nmax ) call DerivedProds("Before",dt_advec)
  !=============================

  call Add_2timing(26,tim_after,tim_before,"phyche:prod")

  !===================================
  call Set_SoilWater()
  call Set_SoilNOx()!hourly

  !===================================
  call init_drydep()
  !===================================

  !=========================================================!
  call debug_concs("PhyChe pre-chem ")

  !************ NOW THE HEAVY BIT **************************!

  if(USE_uEMEP)call uemep_emis(current_date)

  call runchem()   !  calls setup subs and runs chemistry

  call Add_2timing(28,tim_after,tim_before,"Runchem")
  call debug_concs("PhyChe post-chem ")

  !*********************************************************!
  !========================================================!


  !/ See if we are calculating any before-after chemistry productions:

  !=============================
  if(nstep==nmax) call DerivedProds("After",dt_advec)
  !=============================

  call Code_timer(tim_before)
  !=============================
  call Add_2timing(34,tim_after,tim_before,"phyche:drydep")

  !=============================
  ! this output needs the 'old' current_date_hour

  call trajectory_out
  !=============================

  !    the following partly relates to end of time step - hourly output
  !    partly not depends on current_date
  !    => add dt_advec to current_date already here


  !====================================
  ts_now = make_timestamp(current_date)

  call add_secs(ts_now,dt_advec)
  current_date = make_current_date(ts_now)

  if(JUMPOVER29FEB.and.current_date%month==2.and.current_date%day==29)then
    if(MasterProc)write(*,*)'Jumping over one day for current_date!'
    if(MasterProc)print "(2(1X,A))",'current date and time before jump:',&
          date2string("YYYY-MM-DD hh:mm:ss",current_date)
    call add_secs(ts_now,24*3600.)
    current_date = make_current_date(ts_now)       
    if(MasterProc)print "(2(1X,A))",'current date and time after jump:',&
        date2string("YYYY-MM-DD hh:mm:ss",current_date)
  endif

  !====================================
  call Add_2timing(35,tim_after,tim_before,"phyche:outs")
  if(ANALYSIS)then
    call main_3dvar(status)   ! 3D-VAR Analysis for "non-Zero hours"
    call CheckStop(status,"main_3dvar in PhyChem_ml/PhyChe")
    call Add_2timing(T_3DVAR,tim_after,tim_before)
  endif
  call wrtxn(current_date,.false.) !Write xn_adv for future nesting
  if(FORECAST.and.USE_POLLEN) call pollen_dump()
  call Add_2timing(18,tim_after,tim_before,"nest: Write")

  End_of_Day=(current_date%seconds==0).and.(current_date%hour==END_OF_EMEPDAY)

  if(End_of_Day.and.MasterProc)then
    print "(a,a)",' End of EMEP-day ',date2string("(hh:mm:ss)",current_date)
    if(DEBUG%PHYCHEM)write(*,"(a20,2i4,i6)") "END_OF_EMEPDAY ", &
      END_OF_EMEPDAY, current_date%hour,current_date%seconds
  endif

  call debug_concs("PhyChe pre-Derived ")
  call Derived(dt_advec,End_of_Day)

  ! Hourly Outputs:
  if(current_date%seconds==0) then

    if(.not.SOURCE_RECEPTOR .and. FREQ_SITE>0 .and.&
      modulo(current_date%hour,FREQ_SITE)==0)  &
      call siteswrt_surf(xn_adv,cfac,xn_shl)

    if(.not.SOURCE_RECEPTOR .and. FREQ_SONDE>0 .and. &
      modulo(current_date%hour,FREQ_SONDE)==0) &
      call siteswrt_sondes(xn_adv,xn_shl)

    if((.not.SOURCE_RECEPTOR.or.FORECAST).and.NHOURLY_OUT>0 .and. &
      modulo(current_date%hour,FREQ_HOURLY)==0) &
      call hourly_out()

  endif

  ! CoDep
  if(modulo(current_date%hour,1)==0) & ! every hour
    call make_so2nh3_24hr(current_date%hour,&
      xn_adv(IXADV_SO2,:,:,KMAX_MID),&
      xn_adv(IXADV_NH3,:,:,KMAX_MID),&
      cfac(IXADV_SO2,:,:),&
      cfac(IXADV_NH3,:,:))

  call Add_2timing(35,tim_after,tim_before,"phyche:outs")

  first_call=.false.
endsubroutine phyche
!--------------------------------------------------------------------------
subroutine debug_concs(txt)
  character(len=*), intent(in) :: txt
  character(len=6), save :: unit
  real :: c1, c2
  integer, save :: ispec, iadv
  logical :: first_call = .true.

  ! Simple sub to print out eg O3 concentrations for different stages
  ! of calculation. Saves lots of messy lines above.

  if(DEBUG%PHYCHEM.and.debug_proc)then
    if(first_call) then
      ispec = DEBUG%ISPEC
      iadv  = DEBUG%ISPEC - NSPEC_SHL
      unit = 'ppbv'
      if(ispec<=NSPEC_SHL) unit='pptv'
      first_call = .false.
    endif

    if(ispec>NSPEC_SHL)then
      c1=xn_adv(iadv,debug_li,debug_lj,KMAX_MID)*PPBINV 
      c2=c1* cfac(iadv,debug_li,debug_lj)
    else
      c1=xn_shl(ispec,debug_li,debug_lj,KMAX_MID)*PPTINV
      c2=-1.0
    endif
    write(*,"(a,2i3,i5,i3,a12,2g12.4,1x,a4)") "debug_concs:"// &
      trim(txt), me, current_date%hour, current_date%seconds, nstep,&
      trim(species(ispec)%name), c1, c2, unit
  endif
endsubroutine debug_concs
!--------------------------------------------------------------------------
endmodule PhyChem_ml
